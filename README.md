# Bafin compliant securities

This set of smart contracts allows to have Bafin compliant security tokens on Cardano.
It follows the latest version of CIP-113 made by Michele Nuzzi, Matteo Coppola and Philip Desarro:
https://github.com/HarmonicLabs/CIPs/tree/master/CIP-meta-assets%20(ERC20-like%20assets)

Bafin requires the user's security tokens to be freezable and to eventually force transfer them when the user requests to remove his ownership.

## Actors

Different actors cover different roles:
* Owner: normally BaFin, owns the token, modify its information, can update the protocol config and sets/updates all the power users
* Power User: set by the owner, can be:
    * Admin: can add/remove users from the Users linked list and can force transfer user tokens to any KYCed and non-blacklisted destination address
    * Minter: can mint new tokens up to the set max limit
    * Burner: can burn tokens
    * Pauser: can stop/resume all transfers at once
    * Blacklister: can blacklist a user
    * KYCer: can confirm that the user is KYCed
    * ForceTransfer: can move tokens from users to any KYCed and non-blacklisted address
* User: Any normal user (wallet or smart contract) that is CIP-113 and that must be KYCed and not blacklisted

## How it works
TODO

## How to compile
The order to compile the contracts applying the proper validator parameters is the following:
1) Decide the owner_credential_hash and the security_asset_name
2) Create the one-shot Config utxo with the unique NFT
3) Compile global_state.mint
4) Compile global_state.spend
5) Create the one-shot GlobalState utxo with the unique NFT
6) Compile minting_logic_script.withdraw
7) Compile the CIP113 issuance_logic_script with minting_logic_script.withdraw hash as parameter
8) Update Config with the correct hashes
9) Compile power_users.mint
10) Compile power_users.spend
11) Compile users.mint
12) Compile users.spend
13) Compile transfer_logic_script.withdraw
14) Compile third_party_transfer_logic_script.withdraw

## Authors
Matteo Coppola, as part of Finest team

# -------------------------
# OLD INFORMATION TO DELETE

## How it works

* Bafin Address can create a new issuer minting an NFT, specifying issuer's stakeCredentials and locking in issuer_manager.
* Bafin Address then can create a SecurityInfo minting an NFT, specifying issuer's stakeCredentials and locking in security_info.
* A issuer can then create a new admin minting an NFT, specifying admin's stakeCredentials and locking in admin_manager.
* A admin can then create a user state minting an NFT, specifying user's stakeCredentials and locking in a dedicated state_manager instance.
* A issuer can then create securities minting them in a dedicated transfer_manager instance.
* Bafin can remove an issuer changing stakeCredentials of his issuer utxo.
* A issuer can edit the security infos for the security_info utxos he controls.
* A issuer can remove an admin changing stakeCredentials of his admin utxo.
* An admin can freeze a user changing stakeCredentials of his state utxo.
* An admin can lock user's securities sending them in a utxo to locked_transfer_manager. 
* An admin can lock user's securities and give them to anyone sending them in a utxo to transfer_manager. 

For each security, there's 1 issuer utxo, 1 security_info utxo, 1 admin utxo, 1 state_manager SC instance and 1 transfer_manager SC instance.
Only 1 locked_transfer_manager SC exists for all the securities, the utxo datum specifies where the securities are coming from.

Following CIP-113, the security tokens can move only inside the transfer_manager and the locked_transfer_manager SCs.

To check if a issuer or an admin is enabled and legit, there must be a utxo in the proper SC with the proper NFT and with the user stakeCredentials.
To check if a user is enabled and legit, there must be a utxo in the state_manager SC with a NFT and the user's stakeCredentials in the datum.
To invalidate a issuer, an admin or a user, you just need to spend his utxo and remove his stakeCredentials.