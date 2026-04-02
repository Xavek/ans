use ans::interface::{
    FeeInfo, IAdminDispatcher, IAdminDispatcherTrait, IAdminSafeDispatcher,
    IAdminSafeDispatcherTrait, IFeeAdminDispatcher, IFeeAdminDispatcherTrait,
    IFeeAdminSafeDispatcher, IFeeAdminSafeDispatcherTrait, IFeeInvestDispatcher,
    IFeeInvestDispatcherTrait, IRegistryDispatcher, IRegistryDispatcherTrait,
    IRegistrySafeDispatcher, IRegistrySafeDispatcherTrait, NameList,
};
use core::num::traits::Zero;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn ADMIN() -> ContractAddress {
    starknet::contract_address_const::<0xad>()
}
fn OWNER() -> ContractAddress {
    starknet::contract_address_const::<0xae>()
}
fn SUFFIX_ADMIN() -> ContractAddress {
    starknet::contract_address_const::<0xaf>()
}
fn USER() -> ContractAddress {
    starknet::contract_address_const::<0xab>()
}

#[starknet::contract]
mod mock_token {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl MockToken of super::IToken<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            let current = self.balances.read(to);
            self.balances.write(to, current + amount);
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'Insufficient balance');
            self.balances.write(sender, sender_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            let caller_balance = self.balances.read(caller);
            assert(caller_balance >= amount, 'Insufficient balance');
            self.balances.write(caller, caller_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            true
        }
    }
}

#[starknet::interface]
pub trait IToken<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[test]
fn test_registry_deploy() {
    let contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    assert(contract_address.into() != 0, 'should deploy');
}

#[test]
fn test_fee_invest_deploy() {
    let contract = declare("FeeInvest").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    Serde::serialize(@OWNER(), ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    assert(contract_address.into() != 0, 'should deploy');
}

#[test]
fn test_mock_token_deploy() {
    let contract = declare("mock_token").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    assert(contract_address.into() != 0, 'should deploy');
}

#[test]
fn test_registry_constructor_zero_admin() {
    let contract = declare("Registry").unwrap().contract_class();
    let zero: ContractAddress = Zero::zero();
    let mut calldata = array![];
    Serde::serialize(@zero, ref calldata);
    let result = contract.deploy(@calldata);
    assert(result.is_err(), 'should revert');
}

#[test]
fn test_fee_invest_constructor_zero_admin() {
    let contract = declare("FeeInvest").unwrap().contract_class();
    let zero: ContractAddress = Zero::zero();
    let mut calldata = array![];
    Serde::serialize(@zero, ref calldata);
    Serde::serialize(@OWNER(), ref calldata);
    let result = contract.deploy(@calldata);
    assert(result.is_err(), 'should revert');
}

#[test]
fn test_fee_invest_constructor_zero_owner() {
    let contract = declare("FeeInvest").unwrap().contract_class();
    let zero: ContractAddress = Zero::zero();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    Serde::serialize(@zero, ref calldata);
    let result = contract.deploy(@calldata);
    assert(result.is_err(), 'should revert');
}

#[test]
fn test_add_suffix_admin() {
    let contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = contract.deploy(@calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.update_protocol_flag(true);
    dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);
}

#[test]
fn test_add_suffix_admin_zero_suffix() {
    let contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = contract.deploy(@calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_suffix_admin(0, SUFFIX_ADMIN()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_SUFFIX', 'wrong error');
        },
    };
}

#[test]
fn test_add_suffix_admin_zero_addr() {
    let contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = contract.deploy(@calldata).unwrap();

    let zero: ContractAddress = Zero::zero();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_suffix_admin('eth', zero) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_INPUT_ADDR', 'wrong error');
        },
    };
}

#[test]
fn test_complete_add_fee_info() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.update_protocol_flag(true);
    dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);
}

#[test]
fn test_complete_add_fee_info_zero_asset() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let zero: ContractAddress = Zero::zero();
    let fee_info = FeeInfo {
        asset_addr: zero,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.complete_add_fee_info('eth', fee_info) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'FEE_ASSET_ZERO', 'wrong error');
        },
    };
}

#[test]
fn test_complete_add_fee_info_invalid_flag() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: false,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.complete_add_fee_info('eth', fee_info) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'FEE_FLAG_INVALID', 'wrong error');
        },
    };
}

#[test]
fn test_complete_add_fee_info_prohibited_suffix() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.complete_add_fee_info('stark', fee_info) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROHIBITED_SUFFIX', 'wrong error');
        },
    };
}

#[test]
fn test_add_fee_info() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);
}

#[test]
fn test_register_zero_name() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.register(0, 'eth') {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_PREFIX', 'wrong error');
        },
    };
}

#[test]
fn test_register_zero_suffix() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.register('name', 0) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_SUFFIX', 'wrong error');
        },
    };
}

#[test]
fn test_register_prohibited_suffix() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.register('name', 'stark') {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROHIBITED_SUFFIX', 'wrong error');
        },
    };
}

#[test]
fn test_register_fee_not_set() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.register('name', 'eth') {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROTOCOL_FLAG_FALSE', 'wrong error');
        },
    };
}

#[test]
fn test_retrieve_address_not_found() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let zero: ContractAddress = Zero::zero();
    let addr = IRegistryDispatcher { contract_address: registry }
        .retrieve_address_from_name('unknown', 'eth');
    assert(addr == zero, 'should be zero');
}

#[test]
fn test_add_config_addrs() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    dispatcher.add_config_addrs(ADMIN(), registry);
    stop_cheat_caller_address(fee_invest);
}

#[test]
fn test_add_vesu_pools() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    dispatcher.update_protocol_flag(true);
    dispatcher.add_vesu_pools(token, ADMIN(), 1_u8);
    stop_cheat_caller_address(fee_invest);
}

#[test]
fn test_add_vesu_pools_zero_key() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let fee_admin_dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    fee_admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(fee_invest);

    start_cheat_caller_address(fee_invest, ADMIN());
    let dispatcher = IFeeAdminSafeDispatcher { contract_address: fee_invest };
    match dispatcher.add_vesu_pools(token, ADMIN(), 0_u8) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_KEY', 'wrong error');
        },
    }
    stop_cheat_caller_address(fee_invest);
}

#[test]
fn test_add_admin() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let fee_admin_dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    fee_admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(fee_invest);

    start_cheat_caller_address(fee_invest, OWNER());
    let dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    dispatcher.add_admin(SUFFIX_ADMIN());
    stop_cheat_caller_address(fee_invest);
}

#[test]
fn test_add_admin_not_owner() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let fee_admin_dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    fee_admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(fee_invest);

    let dispatcher = IFeeAdminSafeDispatcher { contract_address: fee_invest };
    match dispatcher.add_admin(SUFFIX_ADMIN()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'NOT_OWNER', 'wrong error');
        },
    };
}

#[test]
fn test_add_config_addrs_not_admin() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let dispatcher = IFeeAdminSafeDispatcher { contract_address: fee_invest };
    match dispatcher.add_config_addrs(ADMIN(), registry) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'NOT_ADMIN', 'wrong error');
        },
    };
}

#[test]
fn test_add_suffix_admin_not_admin() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'NOT_ADMIN', 'wrong error');
        },
    };
}

#[test]
fn test_update_protocol_flag_registry() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);
}

#[test]
fn test_update_protocol_flag_registry_not_admin() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.update_protocol_flag(true) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'NOT_ADMIN', 'wrong error');
        },
    };
}

#[test]
fn test_add_suffix_admin_flag_disabled() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROTOCOL_FLAG_FALSE', 'wrong error');
        },
    };
}

#[test]
fn test_complete_add_fee_info_flag_disabled() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.complete_add_fee_info('eth', fee_info) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROTOCOL_FLAG_FALSE', 'wrong error');
        },
    };
}

#[test]
fn test_register_flag_disabled() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.register('name', 'eth') {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROTOCOL_FLAG_FALSE', 'wrong error');
        },
    };
}

#[test]
fn test_update_protocol_flag_fee_invest() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(fee_invest);
}

#[test]
fn test_update_protocol_flag_fee_invest_not_admin() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let dispatcher = IFeeAdminSafeDispatcher { contract_address: fee_invest };
    match dispatcher.update_protocol_flag(true) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'NOT_ADMIN', 'wrong error');
        },
    };
}

#[test]
fn test_add_vesu_pools_flag_disabled() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let dispatcher = IFeeAdminSafeDispatcher { contract_address: fee_invest };
    match dispatcher.add_vesu_pools(token, ADMIN(), 1_u8) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROTOCOL_FLAG_FALSE', 'wrong error');
        },
    };
}

#[test]
fn test_add_admin_flag_disabled() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let dispatcher = IFeeAdminSafeDispatcher { contract_address: fee_invest };
    match dispatcher.add_admin(SUFFIX_ADMIN()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'PROTOCOL_FLAG_FALSE', 'wrong error');
        },
    };
}

#[test]
fn test_add_fee_investor() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.add_fee_investor(USER());
    stop_cheat_caller_address(registry);
}

#[test]
fn test_add_fee_investor_zero_addr() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let zero: ContractAddress = Zero::zero();
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_fee_investor(zero) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_INPUT_ADDR', 'wrong error');
        },
    };
}

#[test]
fn test_add_fee_investor_not_admin() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_fee_investor(USER()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'NOT_ADMIN', 'wrong error');
        },
    };
}

#[test]
fn test_retrieve_name_from_address() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };

    let names: NameList = reg_dispatcher.retrieve_name_from_address(USER(), 'eth');
    assert(names.names.len() == 0, 'should have 0 names');
    assert(names.suffix == 'eth', 'wrong suffix');
}

#[test]
fn test_retrieve_name_from_address_zero_addr() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let zero: ContractAddress = Zero::zero();
    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.retrieve_name_from_address(zero, 'eth') {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_INPUT_ADDR', 'wrong error');
        },
    };
}

#[test]
fn test_retrieve_name_from_address_zero_suffix() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.retrieve_name_from_address(USER(), 0) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_SUFFIX', 'wrong error');
        },
    };
}

#[test]
fn test_retrieve_name_from_address_no_names() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let dispatcher = IRegistryDispatcher { contract_address: registry };
    let names: NameList = dispatcher.retrieve_name_from_address(USER(), 'eth');
    assert(names.names.len() == 0, 'should have 0 names');
    assert(names.suffix == 'eth', 'wrong suffix');
}

#[test]
fn test_full_registration_flow_with_fee() {
    let fi_contract = declare("FeeInvest").unwrap().contract_class();
    let mut fi_calldata = array![];
    Serde::serialize(@ADMIN(), ref fi_calldata);
    Serde::serialize(@OWNER(), ref fi_calldata);
    let (fee_invest, _) = fi_contract.deploy(@fi_calldata).unwrap();

    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(fee_invest, ADMIN());
    let fee_admin_dispatcher = IFeeAdminDispatcher { contract_address: fee_invest };
    fee_admin_dispatcher.add_config_addrs(ADMIN(), registry);
    fee_admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(fee_invest);

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_fee_investor(fee_invest);
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let resolved_addr = reg_dispatcher.retrieve_address_from_name('alice', 'eth');
    assert(resolved_addr.into() == 0, 'should be zero');
}

#[test]
fn test_register_already_registered_name() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };

    let zero: ContractAddress = Zero::zero();
    let addr = reg_dispatcher.retrieve_address_from_name('alice', 'eth');
    assert(addr == zero, 'should be zero');
}

// ============ VIEW FUNCTION TESTS ============

#[test]
fn test_get_suffix_fee_details() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let retrieved_fee_info = reg_dispatcher.get_suffix_fee_details('eth');
    assert(retrieved_fee_info.asset_addr == token, 'wrong asset addr');
    assert(retrieved_fee_info.amount == 100_u256, 'wrong amount');
    assert(retrieved_fee_info.flag == true, 'wrong flag');
    assert(retrieved_fee_info.rev_share_bps == 1000_u256, 'wrong rev share bps');
    let user_addr = starknet::contract_address_const::<0xab>();
    assert(retrieved_fee_info.rev_share_receiver == user_addr, 'wrong rev share receiver');
}

#[test]
fn test_get_suffix_fee_details_unregistered() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let zero: ContractAddress = Zero::zero();
    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let fee_info = reg_dispatcher.get_suffix_fee_details('eth');
    assert(fee_info.asset_addr == zero, 'should be zero');
    assert(fee_info.amount == 0_u256, 'should be zero');
}

#[test]
fn test_gets_suffix_admin() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let suffix_admin = reg_dispatcher.gets_suffix_admin('eth');
    let zero: ContractAddress = Zero::zero();
    assert(suffix_admin != zero, 'suffix admin should be set');
}

#[test]
fn test_gets_suffix_admin_unregistered() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let zero: ContractAddress = Zero::zero();
    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let suffix_admin = reg_dispatcher.gets_suffix_admin('eth');
    assert(suffix_admin == zero, 'should be zero');
}

#[test]
fn test_is_suffix_registered_true() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let is_registered = reg_dispatcher.is_suffix_registered('eth');
    assert(is_registered == true, 'should be registered');
}

#[test]
fn test_is_suffix_registered_false() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let is_registered = reg_dispatcher.is_suffix_registered('eth');
    assert(is_registered == false, 'should not be registered');
}

#[test]
fn test_protocol_status_enabled() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let status = reg_dispatcher.protocol_status();
    assert(status == true, 'should be enabled');
}

#[test]
fn test_protocol_status_disabled() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let status = reg_dispatcher.protocol_status();
    assert(status == false, 'should be disabled');
}

#[test]
fn test_get_suffix_mint_count_initial() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let count = reg_dispatcher.get_suffix_mint_count('eth');
    assert(count == 0, 'initial count should be zero');
}

#[test]
fn test_get_suffix_mint_count_zero_suffix() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let dispatcher = IRegistrySafeDispatcher { contract_address: registry };
    match dispatcher.get_suffix_mint_count(0) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_SUFFIX', 'wrong error');
        },
    };
}

#[test]
fn test_is_name_available_true() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let is_available = reg_dispatcher.is_name_available('unregistered', 'eth');
    assert(is_available == true, 'should be available');
}

#[test]
fn test_is_name_available_zero_name() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let is_available = reg_dispatcher.is_name_available(0, 'eth');
    assert(is_available == true, 'zero name should return true');
}

#[test]
fn test_is_name_available_zero_suffix() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut calldata = array![];
    Serde::serialize(@ADMIN(), ref calldata);
    let (registry, _) = reg_contract.deploy(@calldata).unwrap();

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let is_available = reg_dispatcher.is_name_available('name', 0);
    assert(is_available == true, 'zero suffix should return true');
}

// ============ REVENUE SHARE TESTS ============

#[test]
fn test_update_rev_share_bps() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.update_rev_share_bps('eth', 2000_u256);
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let updated_fee_info = reg_dispatcher.get_suffix_fee_details('eth');
    assert(updated_fee_info.rev_share_bps == 2000_u256, 'rev share should be updated');
}

#[test]
fn test_update_rev_share_bps_not_suffix_admin() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, USER());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.update_rev_share_bps('eth', 2000_u256) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'INVALID_SUFFIX_ADMIN', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}

#[test]
fn test_update_rev_share_bps_exceeds_max() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.update_rev_share_bps('eth', 5000_u256) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'INVALID_REV_BPS', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}

#[test]
fn test_update_rev_share_bps_suffix_not_registered() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.update_rev_share_bps('eth', 2000_u256) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'SUFFIX_NOT_REG', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}

#[test]
fn test_update_rev_share_receiver() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminDispatcher { contract_address: registry };
    dispatcher.update_rev_share_receiver('eth', OWNER());
    stop_cheat_caller_address(registry);

    let reg_dispatcher = IRegistryDispatcher { contract_address: registry };
    let updated_fee_info = reg_dispatcher.get_suffix_fee_details('eth');
    let owner_addr = starknet::contract_address_const::<0xae>();
    assert(updated_fee_info.rev_share_receiver == owner_addr, 'wrong rev share receiver');
}

#[test]
fn test_update_rev_share_receiver_not_suffix_admin() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    admin_dispatcher.complete_add_fee_info('eth', fee_info);
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, USER());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.update_rev_share_receiver('eth', OWNER()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'INVALID_SUFFIX_ADMIN', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}

#[test]
fn test_update_rev_share_receiver_suffix_not_registered() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.update_rev_share_receiver('eth', OWNER()) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'SUFFIX_NOT_REG', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}

// ============ ADD_FEE_INFO VALIDATION TESTS ============

#[test]
fn test_add_fee_info_zero_rev_share_receiver() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let zero: ContractAddress = Zero::zero();
    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 1000_u256,
        rev_share_receiver: zero,
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_fee_info('eth', fee_info) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'ZERO_REV_SHARE_RECEIV', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}

#[test]
fn test_add_fee_info_invalid_rev_bps() {
    let reg_contract = declare("Registry").unwrap().contract_class();
    let mut reg_calldata = array![];
    Serde::serialize(@ADMIN(), ref reg_calldata);
    let (registry, _) = reg_contract.deploy(@reg_calldata).unwrap();

    let token_contract = declare("mock_token").unwrap().contract_class();
    let (token, _) = token_contract.deploy(@ArrayTrait::new()).unwrap();

    let fee_info = FeeInfo {
        asset_addr: token,
        amount: 100_u256,
        flag: true,
        rev_share_bps: 5000_u256,
        rev_share_receiver: USER(),
    };

    start_cheat_caller_address(registry, ADMIN());
    let admin_dispatcher = IAdminDispatcher { contract_address: registry };
    admin_dispatcher.update_protocol_flag(true);
    admin_dispatcher.add_suffix_admin('eth', SUFFIX_ADMIN());
    stop_cheat_caller_address(registry);

    start_cheat_caller_address(registry, SUFFIX_ADMIN());
    let dispatcher = IAdminSafeDispatcher { contract_address: registry };
    match dispatcher.add_fee_info('eth', fee_info) {
        Result::Ok(_) => core::panic_with_felt252('Should revert'),
        Result::Err(x) => {
            let err_data = x;
            assert(err_data.at(0) == @'INVALID_REV_BPS', 'wrong error');
        },
    }
    stop_cheat_caller_address(registry);
}
