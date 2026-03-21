use starknet::ContractAddress;

#[derive(Drop, Serde)]
pub struct NameList {
    pub names: Array<felt252>,
    pub suffix: felt252,
}

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub struct FeeInfo {
    pub asset_addr: ContractAddress,
    pub amount: u256,
    pub flag: bool,
    pub rev_share_bps: u256,
    pub rev_share_receiver: ContractAddress,
}

#[starknet::interface]
pub trait IRegistry<TContractState> {
    /// Register name to address
    fn register(ref self: TContractState, name: felt252, suffix: felt252);
    /// Retrieve name to address
    fn retrieve_address_from_name(
        self: @TContractState, name: felt252, suffix: felt252,
    ) -> ContractAddress;
    /// Retrieve name from address
    fn retrieve_name_from_address(
        self: @TContractState, addr: ContractAddress, suffix: felt252,
    ) -> NameList;
    fn get_suffix_fee_details(self: @TContractState, suffix:felt252) -> FeeInfo;

    fn gets_suffix_admin(self: @TContractState, suffix: felt252) -> ContractAddress;
    fn is_suffix_registered(self: @TContractState, suffix: felt252) -> bool;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait IAdmin<TContractState> {
    fn add_fee_info(ref self: TContractState, suffix: felt252, fee_info: FeeInfo);
    fn complete_add_fee_info(ref self: TContractState, suffix: felt252, fee_info: FeeInfo);
    fn add_suffix_admin(ref self: TContractState, suffix: felt252, addr: ContractAddress);
    fn add_fee_investor(ref self: TContractState, addr: ContractAddress);
    fn update_protocol_flag(ref self: TContractState, flag: bool);
    fn update_rev_share_bps(ref self: TContractState, suffix: felt252, rev_share_bps: u256);
    fn update_rev_share_receiver(ref self: TContractState, suffix: felt252, receiver: ContractAddress);
}

#[starknet::interface]
pub trait IVesu<TContractState> {
    fn deposit(ref self: TContractState, assets: u256, receiver: ContractAddress) -> u256;
    fn max_withdraw(self: @TContractState, owner: ContractAddress) -> u256;
    fn withdraw(
        ref self: TContractState, assets: u256, receiver: ContractAddress, owner: ContractAddress,
    ) -> u256;
}

#[starknet::interface]
pub trait IFeeInvest<TContractState> {
    fn deposit_fees(
        ref self: TContractState,
        asset_addr: ContractAddress,
        receiver: ContractAddress,
        rev_share: u256,
        rev_share_receiver: ContractAddress,
    );
}

#[starknet::interface]
pub trait IFeeAdmin<TContractState> {
    fn add_config_addrs(
        ref self: TContractState, fee_receiver: ContractAddress, registry: ContractAddress,
    );
    fn add_vesu_pools(
        ref self: TContractState, asset: ContractAddress, vesu_vpool: ContractAddress, key: u8,
    );

    fn add_admin(ref self: TContractState, admin: ContractAddress);
    fn update_protocol_flag(ref self: TContractState, flag: bool);
}
