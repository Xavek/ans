#[starknet::contract]
mod FeeInvest {
    use ans::interface::{
        IERC20Dispatcher, IERC20DispatcherTrait, IFeeAdmin, IFeeInvest, IVesuDispatcher,
        IVesuDispatcherTrait,
    };
    use ans::{errors, events};
    use core::num::traits::zero::Zero;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        fee_receiver: ContractAddress,
        vesu_pools: Map<u8, ContractAddress>,
        asset_addr: Map<ContractAddress, u8>,
        admin: ContractAddress,
        owner: ContractAddress,
        registry: ContractAddress,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        ProtocolFeeEvent: events::ProtocolFeeEvent,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress, owner: ContractAddress) {
        assert(admin.is_non_zero(), errors::ZERO_ADMIN);
        assert(owner.is_non_zero(), errors::ZERO_OWNER);
        self.admin.write(admin);
        self.owner.write(owner);
    }

    #[abi(embed_v0)]
    impl FeeAdminImpl of IFeeAdmin<ContractState> {
        fn add_config_addrs(
            ref self: ContractState, fee_receiver: ContractAddress, registry: ContractAddress,
        ) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);
            self.fee_receiver.write(fee_receiver);
            self.registry.write(registry);
        }
        fn add_vesu_pools(
            ref self: ContractState, asset: ContractAddress, vesu_vpool: ContractAddress, key: u8,
        ) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);
            assert(key.is_non_zero(), errors::ZERO_KEY);
            self.vesu_pools.write(key, vesu_vpool);
            self.asset_addr.write(asset, key);
        }
    }

    #[abi(embed_v0)]
    impl FeeInvestImpl of IFeeInvest<ContractState> {
        fn deposit_fees(
            ref self: ContractState, asset_addr: ContractAddress, receiver: ContractAddress,
        ) {
            assert(get_caller_address() == self.registry.read(), errors::NOT_REGISTRY);
            let asset_dispatcher = self.get_token_dispatcher(asset_addr);
            let balance = asset_dispatcher.balanceOf(get_contract_address());
            if (balance > 0) {
                self.deposit_vesu_pool(asset_dispatcher, asset_addr, balance, receiver);
            }
        }
    }


    #[generate_trait]
    impl FeeInvestInternal of FeeInvestInternalTrait {
        fn get_token_dispatcher(
            self: @ContractState, asset_addr: ContractAddress,
        ) -> IERC20Dispatcher {
            IERC20Dispatcher { contract_address: asset_addr }
        }

        fn deposit_vesu_pool(
            ref self: ContractState,
            erc20_dispatcher: IERC20Dispatcher,
            asset_addr: ContractAddress,
            amount: u256,
            receiver: ContractAddress,
        ) {
            let pool_key = self.asset_addr.entry(asset_addr).read();
            let pool_address = self.vesu_pools.entry(pool_key).read();
            if (pool_address.is_non_zero()) {
                let fee_amount = amount / 2;
                erc20_dispatcher.transfer(self.fee_receiver.read(), fee_amount);
                if (amount - fee_amount > 0) {
                    self._handle_vesu_ops(amount - fee_amount, pool_address, asset_addr, receiver);
                }

                self
                    .emit(
                        events::ProtocolFeeEvent {
                            receiver: self.fee_receiver.read(),
                            amount: fee_amount,
                            token: asset_addr,
                        },
                    );
            } else {
                erc20_dispatcher.transfer(self.fee_receiver.read(), amount);
                self
                    .emit(
                        events::ProtocolFeeEvent {
                            receiver: self.fee_receiver.read(), amount: amount, token: asset_addr,
                        },
                    );
            }
        }

        fn _handle_vesu_ops(
            ref self: ContractState,
            amount: u256,
            vesuVTokenAddress: ContractAddress,
            asset_addr: ContractAddress,
            receiver: ContractAddress,
        ) {
            IERC20Dispatcher { contract_address: asset_addr }.approve(vesuVTokenAddress, amount);
            IVesuDispatcher { contract_address: vesuVTokenAddress }.deposit(amount, receiver);
        }
    }
}
