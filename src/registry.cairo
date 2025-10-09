use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store, PartialEq)]
pub struct FeeInfo {
    pub asset_addr: ContractAddress,
    pub amount: u256,
    pub flag: bool,
}

#[starknet::contract]
mod Registry {
    use ans::errors;
    use ans::interface::{IERC20Dispatcher, IERC20DispatcherTrait, IRegistry, Name};
    use core::num::traits::zero::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use super::FeeInfo;

    #[storage]
    struct Storage {
        name_to_address: Map<felt252, Map<felt252, ContractAddress>>,
        address_to_name: Map<ContractAddress, Map<felt252, felt252>>,
        fee_info: Map<felt252, FeeInfo>,
        fee_receiver: ContractAddress,
    }

    #[abi(embed_v0)]
    impl RegistryImpl of IRegistry<ContractState> {
        fn register(ref self: ContractState, name: felt252, suffix: felt252, fee_key: felt252) {
            assert(name.is_non_zero(), errors::ZERO_PREFIX);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(fee_key.is_non_zero(), errors::ZERO_FEE_KEY);

            self.not_registered(name, suffix);
            let caller = get_caller_address();
            let fee_struct = self.get_suffix_details(fee_key);
            self.take_fees(caller, fee_struct);
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
    }
}
