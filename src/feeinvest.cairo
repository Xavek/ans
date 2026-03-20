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
        protocol_flag: bool,
        max_rev_share_bps: u256,
        invest_bps: u256,
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
        self.max_rev_share_bps.write(3000_u256);
        self.invest_bps.write(4000_u256);
    }

    #[abi(embed_v0)]
    impl FeeAdminImpl of IFeeAdmin<ContractState> {
        fn add_config_addrs(
            ref self: ContractState, fee_receiver: ContractAddress, registry: ContractAddress,
        ) {
            self.assert_is_admin();
            self.fee_receiver.write(fee_receiver);
            self.registry.write(registry);
        }
        fn add_vesu_pools(
            ref self: ContractState, asset: ContractAddress, vesu_vpool: ContractAddress, key: u8,
        ) {
            self.protocol_flag_check();
            self.assert_is_admin();
            assert(key.is_non_zero(), errors::ZERO_KEY);
            self.vesu_pools.write(key, vesu_vpool);
            self.asset_addr.write(asset, key);
        }

        fn add_admin(ref self: ContractState, admin: ContractAddress) {
            self.protocol_flag_check();
            let caller = get_caller_address();
            assert(caller == self.owner.read(), errors::NOT_OWNER);
            self.admin.write(admin);
        }

        fn update_protocol_flag(ref self: ContractState, flag: bool) {
            self.assert_is_admin();
            self.protocol_flag.write(flag);
        }
    }

    #[abi(embed_v0)]
    impl FeeInvestImpl of IFeeInvest<ContractState> {
        fn deposit_fees(
            ref self: ContractState,
            asset_addr: ContractAddress,
            receiver: ContractAddress,
            rev_share: u256,
            rev_share_receiver: ContractAddress,
        ) {
            self.protocol_flag_check();
            assert(get_caller_address() == self.registry.read(), errors::NOT_REGISTRY);
            let asset_dispatcher = self.get_token_dispatcher(asset_addr);
            let balance = asset_dispatcher.balanceOf(get_contract_address());
            if (balance > 0) {
                self
                    .deposit_vesu_pool(
                        asset_dispatcher,
                        asset_addr,
                        balance,
                        receiver,
                        rev_share,
                        rev_share_receiver,
                    );
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
            rev_share: u256,
            rev_share_receiver: ContractAddress,
        ) {
            let pool_key = self.asset_addr.entry(asset_addr).read();
            let pool_address = self.vesu_pools.entry(pool_key).read();
            if (pool_address.is_non_zero()) {
                let (invest_amount, rev_share_amount, protocol_fee_amount) = self
                    ._calculate_amounts(amount, rev_share);
                if (invest_amount > 0) {
                    self._handle_vesu_ops(invest_amount, pool_address, asset_addr, receiver);
                }
                if (protocol_fee_amount > 0) {
                    erc20_dispatcher.transfer(self.fee_receiver.read(), protocol_fee_amount);
                }

                if (rev_share_amount > 0) {
                    erc20_dispatcher.transfer(rev_share_receiver, rev_share_amount);
                }

                self
                    .emit(
                        events::ProtocolFeeEvent {
                            receiver: self.fee_receiver.read(),
                            amount: protocol_fee_amount,
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

        fn protocol_flag_check(self: @ContractState) {
            assert(self.protocol_flag.read(), errors::PROTOCOL_FLAG_FALSE);
        }

        fn assert_is_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);
        }

        fn _calculate_amounts(
            self: @ContractState, amount: u256, rev_share: u256,
        ) -> (u256, u256, u256) {
            let invest_amount = amount * self.invest_bps.read() / 10000_u256;
            if (rev_share > 0) {
                let rev_share_amount = amount * rev_share / 10000_u256;
                let protocol_fee_receiver = amount - invest_amount - rev_share_amount;
                (invest_amount, rev_share_amount, protocol_fee_receiver)
            } else {
                let protocol_fee_receiver = amount - invest_amount;
                (invest_amount, 0_u256, protocol_fee_receiver)
            }
        }
    }
}
