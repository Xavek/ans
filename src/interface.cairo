use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, PartialEq)]
pub struct Name {
    pub prefix: felt252,
    pub suffix: felt252,
}

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub struct FeeInfo {
    pub asset_addr: ContractAddress,
    pub amount: u256,
    pub flag: bool,
}

#[starknet::interface]
pub trait IRegistry<TContractState> {
    /// Register name to address
    fn register(ref self: TContractState, name: felt252, suffix: felt252, fee_key: felt252);
    /// Retrieve name to address
    fn retrieve_address_from_name(
        self: @TContractState, name: felt252, suffix: felt252,
    ) -> ContractAddress;
    /// Retrieve name from address
    fn retrieve_name_from_address(
        self: @TContractState, addr: ContractAddress, suffix: felt252,
    ) -> Name;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
}

#[starknet::interface]
pub trait IAdmin<TContractState> {
    fn add_fee_info(ref self: TContractState, suffix: felt252, fee_info: FeeInfo);
    fn complete_add_fee_info(ref self: TContractState, suffix: felt252, fee_info: FeeInfo);
    fn add_suffix_admin(ref self: TContractState, suffix: felt252, addr: ContractAddress);
}
