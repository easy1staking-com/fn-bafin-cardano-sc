# Bafin compliant securities

This set of smart contracts allows to have Bafin compliant security tokens on Cardano.
It follows the latest version of CIP-113 made by Michele Nuzzi, Matteo Coppola and Philip Desarro:
https://github.com/HarmonicLabs/CIPs/tree/master/CIP-meta-assets%20(ERC20-like%20assets)

Bafin requires the user's security tokens to be freezable and to eventually force transfer them when the user requests to remove his ownership.

## Actors
Different actors cover different roles:
* Owner: owns the token, modify its information, can update the protocol config and sets/updates all the power users
* Power User: set by the owner, can be:
    * Admin: can add/remove users from the Users linked list
    * Minter: can mint new tokens up to the set max limit
    * Burner: can burn tokens
    * Pauser: can stop/resume all transfers at once
    * Blacklister: can blacklist a user, adding him to the Users linked list if missing
    * Verifier: can verify the user (KYC), adding him to the Users linked list if missing
    * ForceTransfer: can move tokens from users to any verified and non-blacklisted address
* User: Any normal user (wallet or smart contract) that is CIP-113 and that must be verified and not blacklisted

## How it works
* A security token creator initializes the protocol and decides which Power Users have certain roles
* Power Users are stored on-chain as a linked list
* Users are stored on-chain as a linked list
* Users can transfer tokens only if they are verified and non-blacklisted
* Some Power Users can seize assets forcing the transfer to a designated already verified User (a wallet or smart contract)
* Some Power Users can verify or blacklist Users
* Some Power Users can pause/unpause transfers globally
* There is a predetermined max amount of tokens that can be minted

## How to initialize the protocol
The order to compile the contracts applying the proper validator parameters is the following:
1) Decide the owner_credential_hash, the security_asset_name and the security_info
2) Compile config.spend
3) Compile config.mint
4) Compile power_users.mint
5) Compile power_users.spend
6) Compile users.mint
7) Compile users.spend
8) Compile global_state.mint
9) Compile global_state.spend
10) Compile minting_logic_script.withdraw
11) Compile the CIP113 issuance_logic_script with minting_logic_script.withdraw hash as parameter
12) Compile transfer_logic_script.withdraw
13) Compile third_party_transfer_logic_script.withdraw
14) Create the one-shot Config utxo with the unique NFT
15) Create the one-shot GlobalState utxo with the unique NFT
16) Add this new token to the CIP113 Registry
17) Initialize power_users linked list
18) Initialize users linked list
19) Assign roles to Power Users
20) Mint tokens and verify Users
21) Mint more/burn tokens, oause/force transfers, add/blacklist users, add/modify power users

## Security token uniqueness
The parameters owner_credential_hash and security_asset_name are applied to some of the validators, which are dependencies of the rest of the validators.
This means that the compiled validator hashes are always different as long as each token creator inizializes the protocol with an always different security_asset_name.
Therefore, also the policy id of the security token will be always different.

## How to retrieve information
For wallets and dApps that want to retrieve data:
1) Go to the CIP113 registry and look for the linked list node with key == this token policy id
2) Read the field global_state to know the NFT that holds the global_state datum
3) Find the utxo and read the global_state datum to know if the transfers are globally paused, the number of tokens to mint, the security info, the Users linked list policy id and the PowerUsers linked list policy id
4) To know the status of a certain user, retrieve the utxo that contains a NFT with policy_id == the Users linked list policy id and that has datum.key == the user credential hash. Parse its User datum

## Authors
Matteo Coppola, as part of Finest team