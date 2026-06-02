/// usr/bin/env jbang "$0" "$@" ; exit $?
///
// @formatter:off
//JAVA 24+

//DEPS com.bloxbean.cardano:cardano-client-lib:0.8.0-pre4
//DEPS com.bloxbean.cardano:cardano-client-backend-blockfrost:0.8.0-pre4
//DEPS com.bloxbean.cardano:aiken-java-binding:0.1.1-preview2
// @formatter:on

import java.io.File;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.bloxbean.cardano.aiken.AikenScriptUtil;
import com.bloxbean.cardano.aiken.AikenTransactionEvaluator;
import com.bloxbean.cardano.client.account.Account;
import com.bloxbean.cardano.client.address.Address;
import com.bloxbean.cardano.client.address.AddressProvider;
import com.bloxbean.cardano.client.api.TransactionEvaluator;
import com.bloxbean.cardano.client.api.UtxoSupplier;
import com.bloxbean.cardano.client.api.model.Amount;
import com.bloxbean.cardano.client.api.model.EvaluationResult;
import com.bloxbean.cardano.client.api.model.Result;
import com.bloxbean.cardano.client.api.model.Utxo;
import com.bloxbean.cardano.client.backend.api.BackendService;
import com.bloxbean.cardano.client.backend.api.DefaultUtxoSupplier;
import com.bloxbean.cardano.client.backend.blockfrost.service.BFBackendService;
import com.bloxbean.cardano.client.common.model.Network;
import com.bloxbean.cardano.client.common.model.Networks;
import com.bloxbean.cardano.client.function.helper.SignerProviders;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintLoader;
import com.bloxbean.cardano.client.plutus.blueprint.PlutusBlueprintUtil;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusContractBlueprint;
import com.bloxbean.cardano.client.plutus.blueprint.model.PlutusVersion;
import com.bloxbean.cardano.client.plutus.blueprint.model.Validator;
import com.bloxbean.cardano.client.plutus.spec.BigIntPlutusData;
import com.bloxbean.cardano.client.plutus.spec.BytesPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ConstrPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ListPlutusData;
import com.bloxbean.cardano.client.plutus.spec.MapPlutusData;
import com.bloxbean.cardano.client.plutus.spec.ExUnits;
import com.bloxbean.cardano.client.plutus.spec.PlutusData;
import com.bloxbean.cardano.client.plutus.spec.PlutusScript;
import com.bloxbean.cardano.client.plutus.spec.PlutusV3Script;
import com.bloxbean.cardano.client.plutus.spec.Redeemer;
import com.bloxbean.cardano.client.plutus.spec.RedeemerTag;
import com.bloxbean.cardano.client.quicktx.QuickTxBuilder;
import com.bloxbean.cardano.client.quicktx.Tx;
import com.bloxbean.cardano.client.quicktx.TxResult;
import com.bloxbean.cardano.client.transaction.spec.Asset;
import com.bloxbean.cardano.client.transaction.spec.TransactionInput;
import com.bloxbean.cardano.client.transaction.spec.TransactionWitnessSet;
import com.bloxbean.cardano.client.transaction.spec.cert.Certificate;
import com.bloxbean.cardano.client.transaction.spec.cert.RegCert;
import com.bloxbean.cardano.client.transaction.spec.cert.StakeCredType;
import com.bloxbean.cardano.client.transaction.spec.cert.StakeCredential;
import com.bloxbean.cardano.client.transaction.spec.cert.StakeRegistration;
import com.bloxbean.cardano.client.util.HexUtil;

public class E2ETest {

    // ── Configuration ───────────────────────────────────────────────────────

    private static final String BLOCKFROST_URL = "http://localhost:8080/api/v1/";
    private static final String BLOCKFROST_PROJECT_ID = "Dummy Key";
    private static final Network NETWORK = Networks.testnet();
    private static final String MNEMONIC =
        "test test test test test test test test test test test test "
        + "test test test test test test test test test test test sauce";

    // Address index used to derive RECEIVER from the same MNEMONIC.
    private static final int RECEIVER_ADDRESS_INDEX = 2;

    private static final BackendService BACKEND =
        new BFBackendService(BLOCKFROST_URL, BLOCKFROST_PROJECT_ID);
    private static final UtxoSupplier UTXOS =
        new DefaultUtxoSupplier(BACKEND.getUtxoService());
    private static final QuickTxBuilder TX_BUILDER = new QuickTxBuilder(BACKEND);
    private static final Account ACCOUNT = Account.createFromMnemonic(NETWORK, MNEMONIC);

    // ── Validator titles in plutus.json ─────────────────────────────────────

    private static final String GS_MINT_TITLE       = "global_state.global_state_mint_validator.mint";
    private static final String GS_SPEND_TITLE      = "global_state.global_state_spend_validator.spend";
    private static final String PU_MINT_TITLE       = "power_users.mint.mint";
    private static final String PU_SPEND_TITLE      = "power_users.power_users_validator.spend";
    private static final String DL_MINT_TITLE       = "denylist.mint.mint";
    private static final String DL_SPEND_TITLE      = "denylist.denylist_validator.spend";
    private static final String MINTING_LOGIC_TITLE = "minting_logic_script.minting_logic_validator.withdraw";
    private static final String TRANSFER_LOGIC_TITLE = "transfer_logic_script.transfer_logic_validator.withdraw";

    // ── Genesis parameters ──────────────────────────────────────────────────

    private static final byte[] GS_ASSET_NAME                   = "GlobalState".getBytes(StandardCharsets.UTF_8);
    private static final byte[] PLACEHOLDER_SECURITY_ASSET_NAME = "TestToken".getBytes(StandardCharsets.UTF_8);
    private static final byte[] REGISTRY_ASSET_NAME_PREFIX      = "RV2-".getBytes(StandardCharsets.UTF_8);
    private static final byte[] LL_NODE_KEY_PREFIX              = "Node".getBytes(StandardCharsets.UTF_8);

    /** Per-parameterisation registry asset name. Keying on the minting_logic
     *  hash keeps registry UTxOs from prior runs (with different parameter
     *  sets) distinct from the current one. */
    private static byte[] registryAssetName() throws Exception {
        return concat(REGISTRY_ASSET_NAME_PREFIX, mintingLogic.script().getScriptHash());
    }

    private static final long INITIAL_MINTABLE_AMOUNT = 10L;
    private static final long SCRIPT_UTXO_LOVELACE    = 5_000_000L;
    private static final long YACI_INDEX_DELAY_MS     = 2_000L;

    // KYC payload constants — must match lib/types/kyc_proof.ak.
    private static final int KYC_TIER_USER       = 0x01;
    // Must match env/default.ak's network_id (compiled into plutus.json).
    private static final int KYC_NETWORK_ID      = 0x00;
    private static final long KYC_PROOF_TTL_MS   = 4_000_000_000_000L;

    // Slot offset added to the current tip when setting a tx's validity-range
    // upper bound. Kept small to stay within yaci-devkit's short safe-zone
    // past the current epoch end.
    private static final long TX_VALIDITY_SLOT_OFFSET = 90L;

    /**
     * Demo Plutus V3 "always succeed" script — serves as both the issuance
     * policy and the registry policy. Security is enforced by GS spend's
     * MintSecurity branch and the minting_logic withdraw-zero, both of which
     * gate the actual mint.
     */
    private static final PlutusV3Script DEMO_FREE_MINT_SCRIPT = PlutusV3Script.builder()
        .type("PlutusScriptV3")
        .cborHex("46450101002499")
        .build();

    /** A parameterised Plutus script paired with its enterprise address
     *  (null if the script is mint-only and the address is irrelevant). */
    private record Script(PlutusScript script, Address address) {}

    // ── Mutable state populated as we go ────────────────────────────────────

    private static Script gsMint, gsSpend, puMint, puSpend, dlMint, dlSpend,
        mintingLogic, transferLogic;
    private static byte[] adminKeyHash;     // 28-byte payment key hash of ACCOUNT
    private static byte[] adminStakeHash;   // 28-byte stake key hash of ACCOUNT
    private static byte[] adminVkey;        // 32-byte ed25519 vkey of the admin (KYC issuer)
    private static Account RECEIVER;        // a separate account derived from MNEMONIC
    private static byte[] receiverStakeHash;

    // ── Main ────────────────────────────────────────────────────────────────

    public static void main(String[] args) throws Exception {
        System.out.println("Account base address: " + ACCOUNT.baseAddress());

        Utxo nonceUtxo = pickNonceUtxo();
        System.out.println("Nonce UTxO: " + nonceUtxo.getTxHash() + "#" + nonceUtxo.getOutputIndex());

        PlutusContractBlueprint blueprint =
            PlutusBlueprintLoader.loadBlueprint(new File("plutus.json"));
        parameteriseScripts(blueprint, nonceUtxo);

        adminKeyHash    = ACCOUNT.hdKeyPair().getPublicKey().getKeyHash();
        adminVkey       = ACCOUNT.hdKeyPair().getPublicKey().getKeyData();
        adminStakeHash  = ACCOUNT.getBaseAddress().getDelegationCredentialHash().orElseThrow();
        // A sibling account derived from the same mnemonic — gives a distinct
        // payment address without managing extra keys.
        RECEIVER = Account.createFromMnemonic(NETWORK, MNEMONIC, 0, RECEIVER_ADDRESS_INDEX);
        receiverStakeHash = RECEIVER.getBaseAddress().getDelegationCredentialHash().orElseThrow();
        System.out.println("Admin key hash: " + HexUtil.encodeHexString(adminKeyHash)
            + " (length: " + adminKeyHash.length + ")");
        System.out.println("Receiver base address: " + RECEIVER.baseAddress());

        runBootstrap(nonceUtxo);
        Thread.sleep(YACI_INDEX_DELAY_MS);

        runAddAdminAsPowerUser();
        Thread.sleep(YACI_INDEX_DELAY_MS);

        runMintDummyRegistry();
        Thread.sleep(YACI_INDEX_DELAY_MS);

        runRegisterMintingLogicCredential();
        Thread.sleep(YACI_INDEX_DELAY_MS);

        runMintSecurityViaWithdraw0();
        Thread.sleep(YACI_INDEX_DELAY_MS);

        runRegisterTransferLogicCredential();
        Thread.sleep(YACI_INDEX_DELAY_MS);

        runTransferSecurity();
    }

    // ── Phase: parameterise all on-chain scripts ────────────────────────────

    private static void parameteriseScripts(PlutusContractBlueprint blueprint, Utxo nonceUtxo) throws Exception {
        // GS mint depends only on the nonce — must be derived first so other
        // scripts can parameterise on its policy id.
        gsMint = mintScript(blueprint, GS_MINT_TITLE, ListPlutusData.of(
            BytesPlutusData.of(HexUtil.decodeHexString(nonceUtxo.getTxHash())),
            BigIntPlutusData.of(nonceUtxo.getOutputIndex())));

        byte[] demoPolicyId = HexUtil.decodeHexString(DEMO_FREE_MINT_SCRIPT.getPolicyId());

        gsSpend = spendScript(blueprint, GS_SPEND_TITLE, ListPlutusData.of(
            BytesPlutusData.of(PLACEHOLDER_SECURITY_ASSET_NAME),
            BytesPlutusData.of(demoPolicyId),
            BytesPlutusData.of(gsMint.script().getScriptHash())));

        PlutusData nonceOutRef = outRefPlutusData(nonceUtxo);

        puMint = mintScript(blueprint, PU_MINT_TITLE, ListPlutusData.of(
            BytesPlutusData.of(gsMint.script().getScriptHash()),
            nonceOutRef));
        puSpend = spendScript(blueprint, PU_SPEND_TITLE, ListPlutusData.of(
            BytesPlutusData.of(gsMint.script().getScriptHash()),
            BytesPlutusData.of(puMint.script().getScriptHash())));

        dlMint = mintScript(blueprint, DL_MINT_TITLE, ListPlutusData.of(
            BytesPlutusData.of(gsMint.script().getScriptHash()),
            nonceOutRef));
        dlSpend = spendScript(blueprint, DL_SPEND_TITLE, ListPlutusData.of(
            BytesPlutusData.of(dlMint.script().getScriptHash())));

        mintingLogic = mintScript(blueprint, MINTING_LOGIC_TITLE, ListPlutusData.of(
            BytesPlutusData.of(PLACEHOLDER_SECURITY_ASSET_NAME),
            BytesPlutusData.of(gsMint.script().getScriptHash()),
            BytesPlutusData.of(demoPolicyId),
            BytesPlutusData.of(puMint.script().getScriptHash())));

        transferLogic = mintScript(blueprint, TRANSFER_LOGIC_TITLE, ListPlutusData.of(
            BytesPlutusData.of(PLACEHOLDER_SECURITY_ASSET_NAME),
            BytesPlutusData.of(gsMint.script().getScriptHash()),
            BytesPlutusData.of(demoPolicyId)));
    }

    // ── Phase: bootstrap genesis ────────────────────────────────────────────

    private static void runBootstrap(Utxo nonceUtxo) throws Exception {

        PlutusData gsInitialDatum = buildGsDatum(
            INITIAL_MINTABLE_AMOUNT,
            adminKeyHash, adminVkey,
            puMint.script().getScriptHash(),
            dlMint.script().getScriptHash());

        // LL mint redeemers: Init { root_output_index }. Output order: GS=0, PU=1, DL=2.
        PlutusData gsMintRedeemer = ConstrPlutusData.of(0);
        PlutusData puInitRedeemer = ConstrPlutusData.of(0, BigIntPlutusData.of(1));
        PlutusData dlInitRedeemer = ConstrPlutusData.of(0, BigIntPlutusData.of(2));

        Asset gsNft     = new Asset("0x" + HexUtil.encodeHexString(GS_ASSET_NAME), BigInteger.ONE);
        Asset puRootNft = new Asset("", BigInteger.ONE);
        Asset dlRootNft = new Asset("", BigInteger.ONE);

        Tx tx = new Tx()
            .collectFrom(List.of(nonceUtxo))
            .mintAsset(gsMint.script(), List.of(gsNft),
                gsMintRedeemer, gsSpend.address().getAddress(), gsInitialDatum)
            .mintAsset(puMint.script(), List.of(puRootNft),
                puInitRedeemer, puSpend.address().getAddress(), linkedListRootDatum())
            .mintAsset(dlMint.script(), List.of(dlRootNft),
                dlInitRedeemer, dlSpend.address().getAddress(), linkedListRootDatum())
            .from(ACCOUNT.baseAddress())
            .withChangeAddress(ACCOUNT.baseAddress());

        submit("Bootstrap", tx, /*adminSig=*/ false);
    }

    // ── Phase: add admin (this account) to the PU linked list ───────────────

    private static void runAddAdminAsPowerUser() throws Exception {
        // Idempotency: skip if the admin is already a node in the PU LL.
        byte[] adminNodeAssetName = concat(LL_NODE_KEY_PREFIX, adminKeyHash);
        if (tryFindUtxoByAsset(puSpend.address().getAddress(),
                puMint.script().getPolicyId(),
                HexUtil.encodeHexString(adminNodeAssetName)).isPresent()) {
            System.out.println("AddPowerUser: admin already in PU linked list — skipping");
            return;
        }

        Utxo gsUtxo  = UTXOS.getAll(gsSpend.address().getAddress()).getFirst();
        Utxo puRoot  = UTXOS.getAll(puSpend.address().getAddress()).getFirst();
        Utxo funding = pickFundingUtxo();

        // Inputs are lex-sorted on (txHash, outputIndex); pin all positions
        // so the redeemer carries deterministic indices.
        int anchorInIdx   = lexIndex(List.of(puRoot, funding), puRoot);
        int anchorOutIdx  = 0;     // updated LL root → output 0
        int newNodeOutIdx = 1;     // new node       → output 1
        int gsRefIdx      = 0;     // GS is the only reference input

        // MintRedeemer::AddPowerUser is variant 2.
        PlutusData addPowerUserRedeemer = ConstrPlutusData.of(2,
            BytesPlutusData.of(adminKeyHash),
            BigIntPlutusData.of(anchorInIdx),
            BigIntPlutusData.of(anchorOutIdx),
            BigIntPlutusData.of(newNodeOutIdx),
            BigIntPlutusData.of(gsRefIdx));

        // The LL spend just delegates shape checks to the mint validator.
        PlutusData spendRedeemer = ConstrPlutusData.of(0);  // StateTransition

        PlutusData updatedRootDatum = linkedListElement(
            rootDataPayload(),
            optionSome(BytesPlutusData.of(adminKeyHash)),
            /*isRoot=*/ true);

        PlutusData newNodeDatum = linkedListElement(
            powerUserData(adminKeyHash,
                /*isAdmin*/ true, /*canMint*/ true, /*canBurn*/ true,
                /*canPause*/ true, /*canForceTransfer*/ true),
            optionNone(),
            /*isRoot=*/ false);

        byte[] newNodeAssetName = concat(LL_NODE_KEY_PREFIX, adminKeyHash);
        Asset newNodeNft = new Asset(
            "0x" + HexUtil.encodeHexString(newNodeAssetName), BigInteger.ONE);

        String puPolicyId = puMint.script().getPolicyId();

        Tx tx = new Tx()
            .collectFrom(puRoot, spendRedeemer)
            .collectFrom(List.of(funding))
            .attachSpendingValidator(puSpend.script())
            .payToContract(puSpend.address().getAddress(),
                List.of(Amount.lovelace(BigInteger.valueOf(SCRIPT_UTXO_LOVELACE)),
                        Amount.asset(puPolicyId, "", BigInteger.ONE)),
                updatedRootDatum)                                       // output 0: updated LL root
            .mintAsset(puMint.script(), List.of(newNodeNft),
                addPowerUserRedeemer,
                puSpend.address().getAddress(), newNodeDatum)           // output 1: new node
            .readFrom(gsUtxo)
            .withChangeAddress(ACCOUNT.baseAddress());

        submit("AddPowerUser", tx, /*adminSig=*/ true);
    }

    // ── Phase: mint a dummy registry node ───────────────────────────────────

    /**
     * Mints one registry NFT carrying an inline datum keyed on the
     * minting_logic and transfer_logic script hashes. Field layout follows
     * utils.derive_issuance_policy_id_from_registry_node — both withdraw-zero
     * handlers look up the issuance policy here at runtime.
     */
    private static void runMintDummyRegistry() throws Exception {
        byte[] assetName = registryAssetName();
        if (tryFindUtxoByAsset(ACCOUNT.baseAddress(),
                DEMO_FREE_MINT_SCRIPT.getPolicyId(),
                HexUtil.encodeHexString(assetName)).isPresent()) {
            System.out.println("Registry: registry NFT already at "
                + ACCOUNT.baseAddress() + " — skipping");
            return;
        }

        byte[] issuancePolicyId   = HexUtil.decodeHexString(DEMO_FREE_MINT_SCRIPT.getPolicyId());
        byte[] mintingLogicHash   = mintingLogic.script().getScriptHash();
        byte[] transferLogicHash  = transferLogic.script().getScriptHash();

        // Indices 2/3/4 carry script `Credential`s (Script = Constr index 1),
        // matching the CIP-113 registry node layout that
        // utils.derive_issuance_policy_id_from_registry_node decodes.
        PlutusData registryDatum = ConstrPlutusData.of(0,
            BytesPlutusData.of(issuancePolicyId),                          // 0: issuance_policy_id
            PlutusData.unit(),                                             // 1: unused
            ConstrPlutusData.of(1, BytesPlutusData.of(mintingLogicHash)),  // 2: minting_logic Script credential (== hashed_params)
            ConstrPlutusData.of(1, BytesPlutusData.of(transferLogicHash)), // 3: transfer_logic Script credential
            PlutusData.unit());                                            // 4: unused (third-party slot)

        Asset registryNft = new Asset(
            "0x" + HexUtil.encodeHexString(assetName),
            BigInteger.ONE);

        Tx tx = new Tx()
            .mintAsset(DEMO_FREE_MINT_SCRIPT, List.of(registryNft),
                PlutusData.unit(),
                ACCOUNT.baseAddress(), registryDatum)
            .from(ACCOUNT.baseAddress())
            .withChangeAddress(ACCOUNT.baseAddress());

        submit("Registry", tx, /*adminSig=*/ false);
    }

    // ── Phase: register the minting_logic stake credential ─────────────────

    /**
     * Registers the minting_logic stake credential in its own tx. The withdraw
     * tx that follows needs the credential to exist in the rewards state.
     * Submitted standalone because cardano-client-lib 0.8.0-pre4 has no
     * script-redeemer overload for {@code Tx.registerStakeAddress(...)}.
     */
    private static void runRegisterMintingLogicCredential() throws Exception {
        Address mlRewardAddr = AddressProvider.getRewardAddress(mintingLogic.script(), NETWORK);

        // The SDK only exposes the pre-Conway StakeRegistration cert; we swap
        // it for a Conway RegCert (with explicit deposit) in preBalanceTx.
        Tx tx = new Tx()
            .registerStakeAddress(mlRewardAddr)
            .attachCertificateValidator(mintingLogic.script())
            .from(ACCOUNT.baseAddress())
            .withChangeAddress(ACCOUNT.baseAddress());

        TxResult result = TX_BUILDER.compose(tx)
            .feePayer(ACCOUNT.baseAddress())
            .collateralPayer(ACCOUNT.baseAddress())
            .withSigner(SignerProviders.signerFrom(ACCOUNT))
            .withTxEvaluator(new AikenTransactionEvaluator(BACKEND))
            .preBalanceTx((bctx, txn) -> {
                List<Certificate> certs = txn.getBody().getCerts();
                if (certs == null) return;
                for (int i = 0; i < certs.size(); i++) {
                    if (!(certs.get(i) instanceof StakeRegistration sr)) continue;
                    StakeCredential cred = sr.getStakeCredential();
                    if (cred.getType() != StakeCredType.SCRIPTHASH) continue;
                    certs.set(i, RegCert.builder()
                        .stakeCredential(cred)
                        .coin(BigInteger.valueOf(2_000_000L))
                        .build());
                    // The cert redeemer is injected here, after the evaluator
                    // has already run, so we pre-supply generous ExUnits. The
                    // publish handler is trivial (`RegisterCredential -> True`).
                    TransactionWitnessSet ws = txn.getWitnessSet();
                    if (ws.getRedeemers() == null) {
                        ws.setRedeemers(new java.util.ArrayList<>());
                    }
                    Redeemer publishRedeemer = Redeemer.builder()
                        .tag(RedeemerTag.Cert)
                        .data(PlutusData.unit())
                        .exUnits(ExUnits.builder()
                            .mem(BigInteger.valueOf(1_000_000))
                            .steps(BigInteger.valueOf(500_000_000))
                            .build())
                        .build();
                    publishRedeemer.setIndex(i);
                    ws.getRedeemers().add(publishRedeemer);
                }

                // The SDK selects collateral before our preBalanceTx hook adds
                // the cert redeemer, so it won't pick one on its own. Conway
                // requires collateral inputs to be pure ADA (or accompanied by
                // a collateral-return output) — pickCollateralUtxo guarantees
                // pure ADA.
                if (txn.getBody().getCollateral() == null
                    || txn.getBody().getCollateral().isEmpty()) {
                    Utxo collateralUtxo = pickCollateralUtxo();
                    txn.getBody().setCollateral(java.util.List.of(
                        TransactionInput.builder()
                            .transactionId(collateralUtxo.getTxHash())
                            .index(collateralUtxo.getOutputIndex())
                            .build()));
                }
            })
            .completeAndWait();
        if (!result.isSuccessful()) {
            String resp = result.getResponse() == null ? "" : result.getResponse();
            // Already-registered → idempotent success on re-run.
            if (resp.contains("StakeKeyRegisteredDELEG")) {
                System.out.println("RegisterMintingLogic: credential already registered — skipping");
                return;
            }
            throw new IllegalStateException("RegisterMintingLogic failed: " + resp);
        }
        System.out.println("RegisterMintingLogic tx: " + result.getValue());
    }

    // ── Phase: mint security token via withdraw-zero ────────────────────────

    /**
     * Spends GS with MintSecurity, references the registry + admin's PU node,
     * withdraws-zero from the minting_logic stake credential to authorise the
     * mint, and emits {@code mintAmount} security tokens under the issuance
     * policy. The new GS output decrements {@code mintable_amount} accordingly.
     */
    private static void runMintSecurityViaWithdraw0() throws Exception {
        long mintAmount = 1L;

        Utxo gsUtxo = findUtxoByAsset(gsSpend.address().getAddress(),
            gsMint.script().getPolicyId(),
            HexUtil.encodeHexString(GS_ASSET_NAME));
        Utxo registryUtxo = findUtxoByAsset(ACCOUNT.baseAddress(),
            DEMO_FREE_MINT_SCRIPT.getPolicyId(),
            HexUtil.encodeHexString(registryAssetName()));
        byte[] puNodeAssetName = concat(LL_NODE_KEY_PREFIX, adminKeyHash);
        Utxo puNode = findUtxoByAsset(puSpend.address().getAddress(),
            puMint.script().getPolicyId(),
            HexUtil.encodeHexString(puNodeAssetName));
        Utxo funding = pickFundingUtxo();

        // Inputs and reference inputs are lex-sorted on the wire; precompute
        // positions so the redeemers carry the right indices.
        int gsInputIdx   = lexIndex(List.of(gsUtxo, funding), gsUtxo);
        int puRefIdx     = lexIndex(List.of(registryUtxo, puNode), puNode);
        int gsOutputIdx  = 0;

        // Redeemers are sorted by tag (Spend → Mint → Cert → Reward); with
        // one Spend, one Mint, one Reward, the issuance Mint sits at index 1.
        int issuancePri  = 1;

        // GlobalStateSpendRedeemer { config_ref_input_index, gs_output_index, MintSecurity{ipri} }.
        PlutusData gsSpendRedeemer = ConstrPlutusData.of(0,
            BigIntPlutusData.of(0),                                    // config_ref_input_index (unused by MintSecurity)
            BigIntPlutusData.of(gsOutputIdx),
            ConstrPlutusData.of(0, BigIntPlutusData.of(issuancePri))); // MintSecurity{ipri}

        // MintingLogicScriptWithdrawRedeemer { gs_in, pu_ref, amount }.
        PlutusData withdrawRedeemer = ConstrPlutusData.of(0,
            BigIntPlutusData.of(gsInputIdx),
            BigIntPlutusData.of(puRefIdx),
            BigIntPlutusData.of(mintAmount));

        PlutusData newGsDatum = buildGsDatum(
            INITIAL_MINTABLE_AMOUNT - mintAmount,
            adminKeyHash, adminVkey,
            puMint.script().getScriptHash(),
            dlMint.script().getScriptHash());

        Asset securityToken = new Asset(
            "0x" + HexUtil.encodeHexString(PLACEHOLDER_SECURITY_ASSET_NAME),
            BigInteger.valueOf(mintAmount));

        // GS UTxO value must be preserved verbatim into the new GS output.
        BigInteger gsLovelace = gsUtxo.getAmount().stream()
            .filter(a -> "lovelace".equals(a.getUnit()))
            .map(Amount::getQuantity)
            .findFirst()
            .orElseThrow(() -> new IllegalStateException("GS UTxO has no lovelace?"));

        String gsPolicyId      = gsMint.script().getPolicyId();
        String gsAssetNameHex  = "0x" + HexUtil.encodeHexString(GS_ASSET_NAME);
        Address mlRewardAddr   = AddressProvider.getRewardAddress(mintingLogic.script(), NETWORK);

        Tx tx = new Tx()
            .collectFrom(gsUtxo, gsSpendRedeemer)
            .collectFrom(List.of(funding))
            .attachSpendingValidator(gsSpend.script())
            // Registry resolves issuance_policy_id; PU node proves can_mint.
            .readFrom(registryUtxo, puNode)
            .mintAsset(DEMO_FREE_MINT_SCRIPT, List.of(securityToken), PlutusData.unit())
            // GS output: value preserved verbatim, datum's mintable_amount decremented.
            .payToContract(gsSpend.address().getAddress(),
                List.of(Amount.lovelace(gsLovelace),
                        Amount.asset(gsPolicyId, gsAssetNameHex, BigInteger.ONE)),
                newGsDatum)
            // Withdraw zero is what runs minting_logic's withdraw handler.
            .withdraw(mlRewardAddr, BigInteger.ZERO, withdrawRedeemer)
            .attachRewardValidator(mintingLogic.script())
            .withChangeAddress(ACCOUNT.baseAddress());

        // ExUnits are set per-redeemer manually below; submission goes through
        // NO_OP_EVALUATOR so those values aren't overwritten. The node still
        // performs full Plutus validation on submission.
        TxResult result = TX_BUILDER.compose(tx)
            .feePayer(ACCOUNT.baseAddress())
            .collateralPayer(ACCOUNT.baseAddress())
            .withSigner(SignerProviders.signerFrom(ACCOUNT))
            .withRequiredSigners(ACCOUNT.getBaseAddress())
            .withTxEvaluator(NO_OP_EVALUATOR)
            // preBalanceTx fires after the SDK has assembled the tx and
            // built the witness set, but before signing/submission. Since
            // NO_OP_EVALUATOR leaves every redeemer's ExUnits at zero — and
            // the ledger rejects script txs whose declared ExUnits are below
            // the script's actual cost — we write usable budgets here
            // ourselves. We're running against yaci-devkit
            // (https://devkit.yaci.xyz/), whose slot numbers start near zero;
            // the in-process Aiken evaluator hardcodes preprod/mainnet
            // genesis and rejects them with SlotTooFarInThePast, and yaci's
            // node-side /utils/txs/evaluate endpoint isn't fully wired up.
            // With no working evaluator we just split the per-tx protocol
            // limits (~14M mem / 10G steps) evenly across redeemers. The
            // submitting node still performs full Plutus validation, so any
            // over-allocation is harmless and any under-allocation surfaces
            // as a real on-chain failure.
            .preBalanceTx((bctx, txn) -> {
                if (txn.getWitnessSet() == null) return;
                if (txn.getWitnessSet().getRedeemers() == null) return;
                List<Redeemer> rds = txn.getWitnessSet().getRedeemers();
                ExUnits each = ExUnits.builder()
                    .mem(BigInteger.valueOf(14_000_000L / Math.max(rds.size(), 1)))
                    .steps(BigInteger.valueOf(10_000_000_000L / Math.max(rds.size(), 1)))
                    .build();
                for (Redeemer r : rds) r.setExUnits(each);
            })
            .completeAndWait();
        if (!result.isSuccessful()) {
            throw new IllegalStateException("MintSecurity failed: " + result.getResponse());
        }
        System.out.println("MintSecurity tx: " + result.getValue());
    }

    // ── Phase: register the transfer_logic stake credential ─────────────────

    /**
     * Registers the transfer_logic stake credential via a Conway RegCert.
     * Mirrors runRegisterMintingLogicCredential — see that method for the
     * rationale behind the StakeRegistration → RegCert swap and manual
     * collateral handling.
     */
    private static void runRegisterTransferLogicCredential() throws Exception {
        Address tlRewardAddr = AddressProvider.getRewardAddress(transferLogic.script(), NETWORK);

        Tx tx = new Tx()
            .registerStakeAddress(tlRewardAddr)
            .attachCertificateValidator(transferLogic.script())
            .from(ACCOUNT.baseAddress())
            .withChangeAddress(ACCOUNT.baseAddress());

        TxResult result = TX_BUILDER.compose(tx)
            .feePayer(ACCOUNT.baseAddress())
            .collateralPayer(ACCOUNT.baseAddress())
            .withSigner(SignerProviders.signerFrom(ACCOUNT))
            .withTxEvaluator(new AikenTransactionEvaluator(BACKEND))
            .preBalanceTx((bctx, txn) -> {
                List<Certificate> certs = txn.getBody().getCerts();
                if (certs == null) return;
                for (int i = 0; i < certs.size(); i++) {
                    if (!(certs.get(i) instanceof StakeRegistration sr)) continue;
                    StakeCredential cred = sr.getStakeCredential();
                    if (cred.getType() != StakeCredType.SCRIPTHASH) continue;
                    certs.set(i, RegCert.builder()
                        .stakeCredential(cred)
                        .coin(BigInteger.valueOf(2_000_000L))
                        .build());
                    TransactionWitnessSet ws = txn.getWitnessSet();
                    if (ws.getRedeemers() == null) {
                        ws.setRedeemers(new java.util.ArrayList<>());
                    }
                    Redeemer publishRedeemer = Redeemer.builder()
                        .tag(RedeemerTag.Cert)
                        .data(PlutusData.unit())
                        .exUnits(ExUnits.builder()
                            .mem(BigInteger.valueOf(1_000_000))
                            .steps(BigInteger.valueOf(500_000_000))
                            .build())
                        .build();
                    publishRedeemer.setIndex(i);
                    ws.getRedeemers().add(publishRedeemer);
                }
                if (txn.getBody().getCollateral() == null
                    || txn.getBody().getCollateral().isEmpty()) {
                    Utxo collateralUtxo = pickCollateralUtxo();
                    txn.getBody().setCollateral(java.util.List.of(
                        TransactionInput.builder()
                            .transactionId(collateralUtxo.getTxHash())
                            .index(collateralUtxo.getOutputIndex())
                            .build()));
                }
            })
            .completeAndWait();
        if (!result.isSuccessful()) {
            String resp = result.getResponse() == null ? "" : result.getResponse();
            if (resp.contains("StakeKeyRegisteredDELEG")) {
                System.out.println("RegisterTransferLogic: credential already registered — skipping");
                return;
            }
            throw new IllegalStateException("RegisterTransferLogic failed: " + resp);
        }
        System.out.println("RegisterTransferLogic tx: " + result.getValue());
    }

    // ── Phase: transfer the security token to the receiver ─────────────────

    /**
     * Sends the security token from the admin to RECEIVER, gated by the
     * transfer_logic withdraw-zero. Carries signed-payload KYC attestations
     * for sender and receiver (both signed by the admin, whose vkey is in
     * the GS datum's trusted_entity_vkeys). Denylist absence is witnessed
     * by the empty DL root UTxO, which covers every key.
     */
    private static void runTransferSecurity() throws Exception {
        String securityTokenUnit =
            DEMO_FREE_MINT_SCRIPT.getPolicyId() + HexUtil.encodeHexString(PLACEHOLDER_SECURITY_ASSET_NAME);

        Utxo senderTokenUtxo = findUtxoByAsset(ACCOUNT.baseAddress(),
            DEMO_FREE_MINT_SCRIPT.getPolicyId(),
            HexUtil.encodeHexString(PLACEHOLDER_SECURITY_ASSET_NAME));
        BigInteger tokenQty = senderTokenUtxo.getAmount().stream()
            .filter(a -> securityTokenUnit.equalsIgnoreCase(a.getUnit()))
            .map(Amount::getQuantity)
            .findFirst()
            .orElseThrow();

        Utxo gsUtxo = findUtxoByAsset(gsSpend.address().getAddress(),
            gsMint.script().getPolicyId(),
            HexUtil.encodeHexString(GS_ASSET_NAME));
        Utxo registryUtxo = findUtxoByAsset(ACCOUNT.baseAddress(),
            DEMO_FREE_MINT_SCRIPT.getPolicyId(),
            HexUtil.encodeHexString(registryAssetName()));
        Utxo dlRoot = UTXOS.getAll(dlSpend.address().getAddress()).getFirst();
        // Avoid double-collecting the same UTxO as both the token-bearing
        // input and the funding input.
        Utxo fundingPick = pickFundingUtxo();
        Optional<Utxo> funding = fundingPick.getTxHash().equals(senderTokenUtxo.getTxHash())
            && fundingPick.getOutputIndex() == senderTokenUtxo.getOutputIndex()
            ? Optional.empty()
            : Optional.of(fundingPick);

        // Reference inputs are lex-sorted on the wire; precompute the positions
        // each redeemer index must point at.
        List<Utxo> refs = List.of(gsUtxo, registryUtxo, dlRoot);
        int gsRefIdx     = lexIndex(refs, gsUtxo);
        int dlRootRefIdx = lexIndex(refs, dlRoot);

        byte[] securityPolicyId = HexUtil.decodeHexString(DEMO_FREE_MINT_SCRIPT.getPolicyId());

        byte[] senderPayload = buildKycPayload(
            adminStakeHash, KYC_TIER_USER, KYC_PROOF_TTL_MS,
            securityPolicyId, KYC_NETWORK_ID);
        byte[] senderSig = signWithAdmin(senderPayload);
        PlutusData senderProof = attestationKycProofPlutusData(senderPayload, senderSig, adminVkey);

        byte[] receiverPayload = buildKycPayload(
            receiverStakeHash, KYC_TIER_USER, KYC_PROOF_TTL_MS,
            securityPolicyId, KYC_NETWORK_ID);
        byte[] receiverSig = signWithAdmin(receiverPayload);
        PlutusData receiverProof = attestationKycProofPlutusData(receiverPayload, receiverSig, adminVkey);

        // TransferLogicScriptAction { source_proof, source_denylist_covering_ref_input_index }.
        PlutusData sourceAction = ConstrPlutusData.of(0,
            senderProof,
            BigIntPlutusData.of(dlRootRefIdx));

        // TransferLogicScriptDestinationAction { destination_proof, destination_denylist_covering_ref_input_index }.
        PlutusData destinationAction = ConstrPlutusData.of(0,
            receiverProof,
            BigIntPlutusData.of(dlRootRefIdx));

        // TransferLogicScriptWithdrawRedeemer { gs_ref_idx, actions_for_each_input, destination_actions }.
        PlutusData transferRedeemer = ConstrPlutusData.of(0,
            BigIntPlutusData.of(gsRefIdx),
            ListPlutusData.of(sourceAction),
            ListPlutusData.of(destinationAction));

        Address tlRewardAddr = AddressProvider.getRewardAddress(transferLogic.script(), NETWORK);

        List<Utxo> txInputs = funding.isPresent()
            ? List.of(senderTokenUtxo, funding.get())
            : List.of(senderTokenUtxo);

        Tx tx = new Tx()
            .collectFrom(txInputs)
            .payToAddress(RECEIVER.baseAddress(),
                List.of(Amount.lovelace(BigInteger.valueOf(SCRIPT_UTXO_LOVELACE)),
                        Amount.asset(DEMO_FREE_MINT_SCRIPT.getPolicyId(),
                            "0x" + HexUtil.encodeHexString(PLACEHOLDER_SECURITY_ASSET_NAME),
                            tokenQty)))
            .readFrom(gsUtxo, registryUtxo, dlRoot)
            .withdraw(tlRewardAddr, BigInteger.ZERO, transferRedeemer)
            .attachRewardValidator(transferLogic.script())
            .from(ACCOUNT.baseAddress())
            .withChangeAddress(ACCOUNT.baseAddress());

        // verify_attestation_proof requires a Finite tx upper-bound. The
        // ledger projects this slot into POSIX time for the ScriptContext,
        // which only works within the era's safe horizon — derive it from
        // the current tip, not a hard-coded far future.
        long currentSlot = BACKEND.getBlockService().getLatestBlock().getValue().getSlot();
        long upperSlot = currentSlot + TX_VALIDITY_SLOT_OFFSET;

        TxResult result = TX_BUILDER.compose(tx)
            .feePayer(ACCOUNT.baseAddress())
            .collateralPayer(ACCOUNT.baseAddress())
            .withSigner(SignerProviders.signerFrom(ACCOUNT))
            .withTxEvaluator(NO_OP_EVALUATOR)
            .validTo(upperSlot)
            // See runMintSecurityViaWithdraw0 for the full rationale. Short
            // version: yaci-devkit (https://devkit.yaci.xyz/) doesn't give us
            // a working tx evaluator, so we set ExUnits ourselves by splitting
            // the per-tx protocol limits evenly across redeemers. The node
            // still performs full Plutus validation on submission.
            .preBalanceTx((bctx, txn) -> {
                if (txn.getWitnessSet() == null) return;
                if (txn.getWitnessSet().getRedeemers() == null) return;
                List<Redeemer> rds = txn.getWitnessSet().getRedeemers();
                ExUnits each = ExUnits.builder()
                    .mem(BigInteger.valueOf(14_000_000L / Math.max(rds.size(), 1)))
                    .steps(BigInteger.valueOf(10_000_000_000L / Math.max(rds.size(), 1)))
                    .build();
                for (Redeemer r : rds) r.setExUnits(each);
            })
            .completeAndWait();
        if (!result.isSuccessful()) {
            throw new IllegalStateException("Transfer failed: " + result.getResponse());
        }
        System.out.println("Transfer tx: " + result.getValue());
    }

    // ── KYC signed-payload helpers ─────────────────────────────────────────

    /**
     * Builds the 66-byte attestation payload per lib/types/kyc_proof.ak layout:
     *   pkh(28) ‖ tier(1) ‖ valid_until_ms_be(8) ‖ security_policy_id(28) ‖ network_id(1)
     */
    private static byte[] buildKycPayload(byte[] userPkh, int tier, long validUntilMs,
                                          byte[] securityPolicyId, int networkId) {
        if (userPkh.length != 28) throw new IllegalArgumentException("user pkh must be 28 bytes");
        if (securityPolicyId.length != 28) throw new IllegalArgumentException("security policy id must be 28 bytes");
        byte[] out = new byte[66];
        System.arraycopy(userPkh, 0, out, 0, 28);
        out[28] = (byte) tier;
        // 8-byte big-endian valid_until_ms.
        for (int i = 0; i < 8; i++) {
            out[29 + i] = (byte) (validUntilMs >>> (8 * (7 - i)));
        }
        System.arraycopy(securityPolicyId, 0, out, 37, 28);
        out[65] = (byte) networkId;
        return out;
    }

    /**
     * Signs {@code payload} with the admin's BIP32-Ed25519 payment key. The
     * resulting 64-byte signature verifies under the admin's 32-byte
     * {@code adminVkey} (which is registered in {@code trusted_entity_vkeys}).
     */
    private static byte[] signWithAdmin(byte[] payload) {
        byte[] extendedPrivKey = ACCOUNT.hdKeyPair().getPrivateKey().getKeyData();
        return com.bloxbean.cardano.client.crypto.config.CryptoConfiguration.INSTANCE
            .getSigningProvider()
            .signExtended(payload, extendedPrivKey);
    }

    /**
     * Wire shape of {@code KycProof::Attestation}:
     *   Constr 0 [ Constr 0 [ B(payload), B(signature), B(issuer_vkey) ] ]
     */
    private static PlutusData attestationKycProofPlutusData(byte[] payload, byte[] signature, byte[] issuerVkey) {
        PlutusData attestationProof = ConstrPlutusData.of(0,
            BytesPlutusData.of(payload),
            BytesPlutusData.of(signature),
            BytesPlutusData.of(issuerVkey));
        return ConstrPlutusData.of(0, attestationProof);
    }

    // ── Submission helper ───────────────────────────────────────────────────

    /** Submits {@code tx} via QuickTxBuilder. If {@code adminSig} is true,
     *  forces the admin pkh into extra_signatories. The
     *  {@code useLocalEvaluator} flag chooses between the in-process
     *  AikenTransactionEvaluator and the backend's /evaluate endpoint. */
    private static void submit(String label, Tx tx, boolean adminSig, boolean useLocalEvaluator) {
        QuickTxBuilder.TxContext ctx = TX_BUILDER.compose(tx)
            .feePayer(ACCOUNT.baseAddress())
            .collateralPayer(ACCOUNT.baseAddress())
            .withSigner(SignerProviders.signerFrom(ACCOUNT));
        if (useLocalEvaluator) {
            ctx = ctx.withTxEvaluator(new AikenTransactionEvaluator(BACKEND));
        }
        if (adminSig) {
            ctx = ctx.withRequiredSigners(ACCOUNT.getBaseAddress());
        }
        TxResult result = ctx.completeAndWait();
        if (!result.isSuccessful()) {
            throw new IllegalStateException(label + " failed: " + result.getResponse());
        }
        System.out.println(label + " tx: " + result.getValue());
    }

    /** Convenience overload — uses the local AikenTransactionEvaluator. */
    private static void submit(String label, Tx tx, boolean adminSig) {
        submit(label, tx, adminSig, /*useLocalEvaluator=*/ true);
    }

    /** Evaluator that returns an empty result list, leaving the redeemers'
     *  pre-set ExUnits untouched. Used when ExUnits are supplied manually
     *  via preBalanceTx and the SDK should not overwrite them. */
    private static final TransactionEvaluator NO_OP_EVALUATOR = new TransactionEvaluator() {
        @Override
        public Result<List<EvaluationResult>> evaluateTx(byte[] cbor, java.util.Set<Utxo> inputUtxos) {
            Result<List<EvaluationResult>> r = Result.success("");
            r.withValue(new ArrayList<>());
            return r;
        }
    };

    // ── Setup helpers ───────────────────────────────────────────────────────

    /** Largest pure-ADA UTxO at the account address. */
    private static Utxo pickNonceUtxo() {
        List<Utxo> all = UTXOS.getAll(ACCOUNT.baseAddress());
        if (all.isEmpty()) {
            throw new IllegalStateException(
                "No UTxOs at " + ACCOUNT.baseAddress() + " — top-up the account?");
        }
        return all.stream()
            .filter(u -> u.getAmount().size() == 1)
            .max(Comparator.comparing(u -> u.getAmount().get(0).getQuantity()))
            .orElse(all.get(0));
    }

    /** Largest pure-ADA UTxO at our base address; auto-tops up via yaci-devkit
     *  if none is available. Conway requires collateral inputs to be pure ADA
     *  (or carry a collateral-return output, which we avoid building manually). */
    private static Utxo pickCollateralUtxo() {
        Optional<Utxo> pureAda = UTXOS.getAll(ACCOUNT.baseAddress()).stream()
            .filter(u -> u.getAmount().size() == 1)
            .max(Comparator.comparing(E2ETest::lovelaceOf));
        if (pureAda.isPresent()) return pureAda.get();
        topupAdmin(10_000L);
        return UTXOS.getAll(ACCOUNT.baseAddress()).stream()
            .filter(u -> u.getAmount().size() == 1)
            .max(Comparator.comparing(E2ETest::lovelaceOf))
            .orElseThrow(() -> new IllegalStateException(
                "No pure-ADA collateral UTxO at " + ACCOUNT.baseAddress()
                + " even after topup"));
    }

    /** Tops up the admin account via yaci-devkit's local-cluster admin API
     *  and waits for the indexer to surface the new UTxO. */
    private static void topupAdmin(long adaAmount) {
        try {
            String body = "{\"address\":\"" + ACCOUNT.baseAddress()
                + "\",\"adaAmount\":" + adaAmount + "}";
            java.net.http.HttpClient.newHttpClient().send(
                java.net.http.HttpRequest.newBuilder(
                        java.net.URI.create("http://localhost:10000/local-cluster/api/addresses/topup"))
                    .header("Content-Type", "application/json")
                    .POST(java.net.http.HttpRequest.BodyPublishers.ofString(body))
                    .build(),
                java.net.http.HttpResponse.BodyHandlers.ofString());
            Thread.sleep(YACI_INDEX_DELAY_MS);
        } catch (Exception e) {
            throw new RuntimeException("Failed to topup admin: " + e.getMessage(), e);
        }
    }

    /** UTxO with the most lovelace at our base address, preferring pure-ADA
     *  but falling back to mixed-asset UTxOs when accumulated tokens from
     *  earlier runs have bundled with all available ADA. */
    private static Utxo pickFundingUtxo() {
        List<Utxo> all = UTXOS.getAll(ACCOUNT.baseAddress());
        Optional<Utxo> pureAda = all.stream()
            .filter(u -> u.getAmount().size() == 1)
            .max(Comparator.comparing(E2ETest::lovelaceOf));
        if (pureAda.isPresent()) return pureAda.get();
        return all.stream()
            .max(Comparator.comparing(E2ETest::lovelaceOf))
            .orElseThrow(() -> new IllegalStateException(
                "No UTxO at " + ACCOUNT.baseAddress()));
    }

    /** Lovelace amount of a UTxO (0 if no lovelace entry — shouldn't happen). */
    private static BigInteger lovelaceOf(Utxo u) {
        return u.getAmount().stream()
            .filter(a -> "lovelace".equals(a.getUnit()))
            .map(Amount::getQuantity)
            .findFirst()
            .orElse(BigInteger.ZERO);
    }

    /** Find the first UTxO at {@code address} carrying the given asset
     *  (policyId concatenated with hex asset name). */
    private static Utxo findUtxoByAsset(String address, String policyId, String assetNameHex) {
        return tryFindUtxoByAsset(address, policyId, assetNameHex).orElseThrow(
            () -> new IllegalStateException("No UTxO with unit "
                + policyId + assetNameHex + " at " + address));
    }

    /** Non-throwing variant of {@link #findUtxoByAsset(String, String, String)}. */
    private static Optional<Utxo> tryFindUtxoByAsset(String address, String policyId, String assetNameHex) {
        String unit = policyId + assetNameHex;
        for (Utxo u : UTXOS.getAll(address)) {
            for (Amount a : u.getAmount()) {
                if (unit.equalsIgnoreCase(a.getUnit())) return Optional.of(u);
            }
        }
        return Optional.empty();
    }

    /** Mint-only script: parameterise but don't derive an address. */
    private static Script mintScript(PlutusContractBlueprint blueprint,
                                     String title, ListPlutusData params) {
        return new Script(applyParams(blueprint, title, params), null);
    }

    /** Spend script: parameterise and derive the enterprise spend address. */
    private static Script spendScript(PlutusContractBlueprint blueprint,
                                      String title, ListPlutusData params) {
        PlutusScript script = applyParams(blueprint, title, params);
        return new Script(script, AddressProvider.getEntAddress(script, NETWORK));
    }

    private static PlutusScript applyParams(PlutusContractBlueprint blueprint,
                                            String title, ListPlutusData params) {
        Validator validator = blueprint.getValidators().stream()
            .filter(v -> v.getTitle().equals(title))
            .findFirst()
            .orElseThrow(() -> new IllegalStateException(
                "Validator not found in plutus.json: " + title));
        String parameterised =
            AikenScriptUtil.applyParamToScript(params, validator.getCompiledCode());
        return PlutusBlueprintUtil.getPlutusScriptFromCompiledCode(
            parameterised, PlutusVersion.v3);
    }

    // ── Datum construction ──────────────────────────────────────────────────

    /** GlobalStateDatum — mirrors lib/types/global_state.ak. The
     *  {@code mintableAmount} is parameterised so the same helper builds the
     *  initial datum and the post-mint decremented datum. */
    private static PlutusData buildGsDatum(long mintableAmount,
                                           byte[] adminKeyHash,
                                           byte[] adminVkey,
                                           byte[] puPolicyId,
                                           byte[] dlPolicyId) {
        MapPlutusData trustedEntityVkeys = MapPlutusData.builder()
            .map(Map.of(BytesPlutusData.of(adminVkey), PlutusData.unit()))
            .build();
        return ConstrPlutusData.of(0,
            plutusBool(false),                          // transfers_paused
            BigIntPlutusData.of(mintableAmount),
            BytesPlutusData.of(adminKeyHash),           // admin_credential_hash
            BytesPlutusData.of(puPolicyId),             // power_user_linked_list_policy_id
            BytesPlutusData.of(dlPolicyId),             // denylist_linked_list_policy_id
            PlutusData.unit(),                          // security_info
            trustedEntityVkeys,
            BytesPlutusData.of(new byte[0]),            // member_root_hash
            plutusBool(false));                         // requires_receiver_kyc
    }

    // ── Generic Plutus data helpers ─────────────────────────────────────────

    private static PlutusData plutusBool(boolean b) {
        return ConstrPlutusData.of(b ? 1 : 0);
    }

    private static PlutusData optionNone() {
        return ConstrPlutusData.of(1);
    }

    private static PlutusData optionSome(PlutusData inner) {
        return ConstrPlutusData.of(0, inner);
    }

    private static PlutusData outRefPlutusData(Utxo utxo) {
        return ConstrPlutusData.of(0,
            BytesPlutusData.of(HexUtil.decodeHexString(utxo.getTxHash())),
            BigIntPlutusData.of(utxo.getOutputIndex()));
    }

    /** Element { data: Root(()), next: None } — the empty LL root datum. */
    private static PlutusData linkedListRootDatum() {
        return linkedListElement(rootDataPayload(), optionNone(), /*isRoot=*/ true);
    }

    /** Root payload: Constr(0) — unit. */
    private static PlutusData rootDataPayload() {
        return ConstrPlutusData.of(0);
    }

    /** Wraps inner data as Root(...) (Constr 0) when isRoot, else Node(...) (Constr 1),
     *  then wraps the element with its link in the outer Element constructor. */
    private static PlutusData linkedListElement(PlutusData innerData, PlutusData link, boolean isRoot) {
        PlutusData elementData = ConstrPlutusData.of(isRoot ? 0 : 1, innerData);
        return ConstrPlutusData.of(0, elementData, link);
    }

    /** PowerUser { credential_hash, is_admin, can_mint, can_burn, can_pause, can_force_transfer }. */
    private static PlutusData powerUserData(byte[] pkh, boolean isAdmin,
                                            boolean canMint, boolean canBurn,
                                            boolean canPause, boolean canForceTransfer) {
        return ConstrPlutusData.of(0,
            BytesPlutusData.of(pkh),
            plutusBool(isAdmin),
            plutusBool(canMint),
            plutusBool(canBurn),
            plutusBool(canPause),
            plutusBool(canForceTransfer));
    }

    // ── Misc utilities ──────────────────────────────────────────────────────

    /** Position of {@code target} in {@code utxos} after lex-sorting on (txHash, outputIndex). */
    private static int lexIndex(List<Utxo> utxos, Utxo target) {
        List<Utxo> sorted = new ArrayList<>(utxos);
        sorted.sort(Comparator.comparing(Utxo::getTxHash)
            .thenComparingInt(Utxo::getOutputIndex));
        return sorted.indexOf(target);
    }

    private static byte[] concat(byte[] a, byte[] b) {
        byte[] out = new byte[a.length + b.length];
        System.arraycopy(a, 0, out, 0, a.length);
        System.arraycopy(b, 0, out, a.length, b.length);
        return out;
    }
}
