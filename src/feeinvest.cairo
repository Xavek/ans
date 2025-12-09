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
    use starknet::{
        ContractAddress, SyscallResultTrait, get_caller_address, get_contract_address, syscalls,
    };

    #[storage]
    struct Storage {
        fee_receiver: ContractAddress,
        harvest_addr: ContractAddress,
        exchanger: ContractAddress,
        reward_asset_addr: ContractAddress,
        vesu_pools: Map<u8, ContractAddress>,
        asset_addr: Map<ContractAddress, u8>,
        admin: ContractAddress,
        owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        DepositToExchangerEvent: events::DepositToExchangerEvent,
        DepositByExchangerEvent: events::DepositByExchangerEvent,
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
            ref self: ContractState,
            fee_receiver: ContractAddress,
            harvest_addr: ContractAddress,
            exchanger: ContractAddress,
            reward_asset_addr: ContractAddress,
        ) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);
            self.fee_receiver.write(fee_receiver);
            self.harvest_addr.write(harvest_addr);
            self.exchanger.write(exchanger);
            self.reward_asset_addr.write(reward_asset_addr);
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
        fn deposit_fees(ref self: ContractState, asset_addr: ContractAddress) {
            let asset_dispatcher = self.get_token_dispatcher(asset_addr);
            let balance = asset_dispatcher.balanceOf(get_contract_address());
            if (balance > 0) {
                let amount = balance / 2;
                asset_dispatcher.transfer(self.fee_receiver.read(), amount);
                if (balance - amount > 0) {
                    self.deposit_vesu_pool(asset_addr, balance - amount);
                }
                self
                    .emit(
                        events::ProtocolFeeEvent {
                            receiver: self.fee_receiver.read(), amount: amount, token: asset_addr,
                        },
                    )
            }
        }

        fn harvest_and_send_to_exchanger(
            ref self: ContractState,
            reward_distributor_contract: ContractAddress,
            entrypoint: felt252,
            amount: u128,
            proof: Span<felt252>,
            calldata: Span<felt252>,
        ) {
            let caller = get_caller_address();
            assert(caller == self.harvest_addr.read(), errors::NOT_HARVEST_KEEPER);
            let mut call_data: Array<felt252> = array![];
            Serde::serialize(@amount, ref call_data);
            Serde::serialize(@proof, ref call_data);

            syscalls::call_contract_syscall(
                reward_distributor_contract, entrypoint, call_data.span(),
            )
                .unwrap_syscall();

            let strk_dispatcher = self.get_token_dispatcher(self.reward_asset_addr.read());
            let strk_current_balance = strk_dispatcher.balanceOf(get_contract_address());
            if (strk_current_balance.is_non_zero()) {
                strk_dispatcher.transfer(self.exchanger.read(), strk_current_balance);
                self
                    .emit(
                        events::DepositToExchangerEvent {
                            exchanger: self.exchanger.read(),
                            amount: strk_current_balance,
                            token: self.reward_asset_addr.read(),
                        },
                    )
            }
        }

        fn deposit_by_exchanger(
            ref self: ContractState, asset_addr: ContractAddress, assets: u256,
        ) {
            assert(assets.is_non_zero(), errors::ZERO_ASSETS);
            let caller = get_caller_address();
            assert(caller == self.exchanger.read(), errors::INVALID_EXCHANGER_ADDRS);
            let asset_dispatcher = self.get_token_dispatcher(asset_addr);
            asset_dispatcher.transferFrom(caller, get_contract_address(), assets);
            self.deposit_fees(asset_addr);
            self
                .emit(
                    events::DepositByExchangerEvent {
                        exchanger: self.exchanger.read(), amount: assets, token: asset_addr,
                    },
                )
        }
    }


    #[generate_trait]
    impl FeeInvestInternal of FeeInvestInternalTrait {
        fn get_token_dispatcher(
            self: @ContractState, asset_addr: ContractAddress,
        ) -> IERC20Dispatcher {
            IERC20Dispatcher { contract_address: asset_addr }
        }

        fn deposit_vesu_pool(ref self: ContractState, asset_addr: ContractAddress, amount: u256) {
            let pool_key = self.asset_addr.entry(asset_addr).read();
            let pool_address = self.vesu_pools.entry(pool_key).read();
            if (pool_address.is_non_zero()) {
                self._handle_vesu_ops(amount, pool_address, asset_addr, true);
            }
        }

        fn _handle_vesu_ops(
            ref self: ContractState,
            amount: u256,
            vesuVTokenAddress: ContractAddress,
            asset_addr: ContractAddress,
            isDeposit: bool,
        ) {
            if (isDeposit) {
                IERC20Dispatcher { contract_address: asset_addr }
                    .approve(vesuVTokenAddress, amount);
                IVesuDispatcher { contract_address: vesuVTokenAddress }
                    .deposit(amount, get_contract_address());
            } else {
                let max_withdraw_amount: u256 = IVesuDispatcher {
                    contract_address: vesuVTokenAddress,
                }
                    .max_withdraw(get_contract_address());

                IVesuDispatcher { contract_address: vesuVTokenAddress }
                    .withdraw(max_withdraw_amount, get_contract_address(), get_contract_address());
            }
        }
    }
}
