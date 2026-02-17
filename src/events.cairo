use starknet::ContractAddress;

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct FeeInfoEvent {
    #[key]
    pub suffix: felt252,
    pub suffix_admin: ContractAddress,
    pub asset_addr: ContractAddress,
    pub amount: u256,
    pub flag: bool,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct FeeInfoCompleteEvent {
    #[key]
    pub suffix: felt252,
    pub admin: ContractAddress,
    pub asset_addr: ContractAddress,
    pub amount: u256,
    pub flag: bool,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct SuffixAdminEvent {
    #[key]
    pub suffix: felt252,
    pub suffix_admin: ContractAddress,
    pub admin: ContractAddress,
}

#[derive(Debug, Drop, PartialEq, starknet::Event)]
pub struct ProtocolFeeEvent {
    pub receiver: ContractAddress,
    pub amount: u256,
    pub token: ContractAddress,
}
