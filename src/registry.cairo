#[starknet::contract]
mod Registry {
    use ans::interface::{
        FeeInfo, IAdmin, IERC20Dispatcher, IERC20DispatcherTrait, IFeeInvestDispatcher,
        IFeeInvestDispatcherTrait, IRegistry, Name,
    };
    use ans::{errors, events};
    use core::num::traits::zero::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    const PROHIBITED_SUFFIX: felt252 = 'stark';

    #[storage]
    struct Storage {
        name_to_address: Map<felt252, Map<felt252, ContractAddress>>,
        address_to_name: Map<ContractAddress, Map<felt252, felt252>>,
        fee_info: Map<felt252, FeeInfo>,
        suffix_admin: Map<felt252, ContractAddress>,
        suffix_log: Map<felt252, u8>,
        admin: ContractAddress,
        fee_investor: ContractAddress,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        FeeInfoEvent: events::FeeInfoEvent,
        FeeInfoCompleteEvent: events::FeeInfoCompleteEvent,
        SuffixAdminEvent: events::SuffixAdminEvent,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        assert(admin.is_non_zero(), errors::ZERO_ADMIN);
        self.admin.write(admin);
    }

    #[abi(embed_v0)]
    impl AdminImpl of IAdmin<ContractState> {
        fn add_fee_info(ref self: ContractState, suffix: felt252, fee_info: FeeInfo) {
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(suffix != PROHIBITED_SUFFIX, errors::PROHIBITED_SUFFIX);
            assert(fee_info.asset_addr.is_non_zero(), errors::FEE_ASSET_ZERO);
            assert(fee_info.flag == true, errors::FEE_FLAG_INVALID);

            let caller = get_caller_address();
            let suffix_admin_addr = self.suffix_admin.read(suffix);
            assert(caller == suffix_admin_addr, errors::SUFFIX_ADMIN_NOT_REGISTER);

            let suffix_count = self.suffix_log.read(suffix);

            assert(suffix_count == 0, errors::SUFFIX_ALREADY_REGISTERED);
            self
                .emit(
                    events::FeeInfoEvent {
                        suffix: suffix,
                        suffix_admin: caller,
                        asset_addr: fee_info.asset_addr,
                        amount: fee_info.amount,
                        flag: fee_info.flag,
                    },
                );
        }
        fn complete_add_fee_info(ref self: ContractState, suffix: felt252, fee_info: FeeInfo) {
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(suffix != PROHIBITED_SUFFIX, errors::PROHIBITED_SUFFIX);
            assert(fee_info.asset_addr.is_non_zero(), errors::FEE_ASSET_ZERO);
            assert(fee_info.flag == true, errors::FEE_FLAG_INVALID);

            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);

            let suffix_count = self.suffix_log.read(suffix);
            assert(suffix_count == 0, errors::SUFFIX_ALREADY_REGISTERED);

            self.suffix_log.write(suffix, 1_u8);
            self.fee_info.write(suffix, fee_info);
            self
                .emit(
                    events::FeeInfoCompleteEvent {
                        suffix: suffix,
                        admin: caller,
                        asset_addr: fee_info.asset_addr,
                        amount: fee_info.amount,
                        flag: fee_info.flag,
                    },
                );
        }
        fn add_suffix_admin(ref self: ContractState, suffix: felt252, addr: ContractAddress) {
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(addr.is_non_zero(), errors::ZERO_INPUT_ADDR);
            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);
            self.suffix_admin.write(suffix, addr);
            self
                .emit(
                    events::SuffixAdminEvent { suffix: suffix, suffix_admin: addr, admin: caller },
                );
        }
    }

    #[abi(embed_v0)]
    impl RegistryImpl of IRegistry<ContractState> {
        fn register(ref self: ContractState, name: felt252, suffix: felt252, fee_key: felt252) {
            assert(name.is_non_zero(), errors::ZERO_PREFIX);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(suffix != PROHIBITED_SUFFIX, errors::PROHIBITED_SUFFIX);
            assert(fee_key.is_non_zero(), errors::ZERO_FEE_KEY);

            self.not_registered(name, suffix);
            let caller = get_caller_address();
            let fee_struct = self.get_suffix_details(fee_key);
            self.take_fees(caller, fee_struct);
            self.send_fees(caller, fee_struct.asset_addr);
            self.name_to_address.entry(suffix).write(name, caller);
            self.address_to_name.entry(caller).write(suffix, name);
        }

        fn retrieve_address_from_name(
            self: @ContractState, name: felt252, suffix: felt252,
        ) -> ContractAddress {
            assert(name.is_non_zero(), errors::ZERO_PREFIX);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);

            self.name_to_address.entry(suffix).read(name)
        }

        fn retrieve_name_from_address(
            self: @ContractState, addr: ContractAddress, suffix: felt252,
        ) -> Name {
            assert(addr.is_non_zero(), errors::ZERO_INPUT_ADDR);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);

            let prefix = self.address_to_name.entry(addr).read(suffix);
            Name { prefix: prefix, suffix: suffix }
        }
    }

    #[generate_trait]
    impl RegistryInternal of RegistryInternalTrait {
        fn not_registered(self: @ContractState, name: felt252, suffix: felt252) {
            let result = self.name_to_address.entry(suffix).read(name);
            assert(result.is_zero(), errors::ALREADY_REGISTERED_NAME);
        }

        fn get_suffix_details(self: @ContractState, fee_key: felt252) -> FeeInfo {
            let fee_struct = self.fee_info.read(fee_key);
            assert(fee_struct.asset_addr.is_non_zero(), errors::FEE_NOT_SET);
            assert(fee_struct.flag, errors::FEE_NOT_SUPPORTED);
            fee_struct
        }

        fn take_fees(ref self: ContractState, sender: ContractAddress, fee_struct: FeeInfo) {
            if (fee_struct.amount > 0) {
                let this = get_contract_address();
                let asset_addr = fee_struct.asset_addr;
                let dispatcher = IERC20Dispatcher { contract_address: asset_addr };
                dispatcher.transferFrom(sender, this, fee_struct.amount);
            }
        }

        fn send_fees(
            ref self: ContractState, receiver: ContractAddress, asset_addr: ContractAddress,
        ) {
            let dispatcher = IERC20Dispatcher { contract_address: asset_addr };
            let balance = dispatcher.balanceOf(get_contract_address());
            if (balance > 0) {
                dispatcher.transfer(self.fee_investor.read(), balance);
                IFeeInvestDispatcher { contract_address: self.fee_investor.read() }
                    .deposit_fees(asset_addr, receiver);
            }
        }
    }
}
