use starknet::ContractAddress;
#[starknet::interface]
pub trait IRegistry<TContractState> {
    /// Register name to address
    fn register(ref self: TContractState, name: felt252, suffix: felt252, fee_key: felt252);
    /// Retrieve name to address
    fn retrieve_address_from_name(
        self: @TContractState, name: felt252, suffix: felt252,
    ) -> ContractAddress;
    /// Retrieve name from address
    fn retrieve_name_from_address(self: @TContractState, addr: ContractAddress) -> felt252;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
}
