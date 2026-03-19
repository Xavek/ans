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

    let fee_info = FeeInfo { asset_addr: token, amount: 100_u256, flag: true };

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
    let fee_info = FeeInfo { asset_addr: zero, amount: 100_u256, flag: true };

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

    let fee_info = FeeInfo { asset_addr: token, amount: 100_u256, flag: false };

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

    let fee_info = FeeInfo { asset_addr: token, amount: 100_u256, flag: true };

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

    let fee_info = FeeInfo { asset_addr: token, amount: 100_u256, flag: true };

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

    let fee_info = FeeInfo { asset_addr: token, amount: 100_u256, flag: true };

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
