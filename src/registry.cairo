use starknet::ContractAddress;

#[starknet::interface]
pub trait IRegistry<TContractState> {
    /// Register name to address
    fn register(ref self: TContractState, name: felt252, suffix: felt252);
    /// Retrieve name to address
    fn retrieve_address_from_name(
        self: @TContractState, name: felt252, suffix: felt252,
    ) -> ContractAddress;
    /// Retrieve name from address
    fn retrieve_name_from_address(self: @TContractState, addr: ContractAddress) -> felt252;
}

#[starknet::contract]
mod Registry {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        name_to_address: Map<felt252, Map<felt252, ContractAddress>>,
        address_to_name: Map<ContractAddress, felt252>,
    }
    #[abi(embed_v0)]
    impl RegistryImpl of super::IRegistry<ContractState> {
        fn register(ref self: ContractState, name: felt252, suffix: felt252) {
            let caller = get_caller_address();
            self.name_to_address.entry(suffix).write(name, caller);
            self.address_to_name.write(caller, name);
        }

        fn retrieve_address_from_name(
            self: @ContractState, name: felt252, suffix: felt252,
        ) -> ContractAddress {
            self.name_to_address.entry(suffix).read(name)
        }

        fn retrieve_name_from_address(self: @ContractState, addr: ContractAddress) -> felt252 {
            self.address_to_name.read(addr)
        }
    }

    #[generate_trait]
    impl RegistryInternal of RegistryInternalTrait {
        fn not_registered(self: @ContractState, name: felt252) {}
    }
}
