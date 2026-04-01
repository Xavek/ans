#[starknet::contract]
mod Registry {
    use ans::interface::{
        FeeInfo, IAdmin, IERC20Dispatcher, IERC20DispatcherTrait, IFeeInvestDispatcher,
        IFeeInvestDispatcherTrait, IRegistry, NameList,
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
        address_name_count: Map<ContractAddress, Map<felt252, u32>>,
        address_to_name: Map<ContractAddress, Map<felt252, Map<u32, felt252>>>,
        suffix_mint_count: Map<felt252, u64>,
        fee_info: Map<felt252, FeeInfo>,
        suffix_admin: Map<felt252, ContractAddress>,
        suffix_log: Map<felt252, u8>,
        admin: ContractAddress,
        fee_investor: ContractAddress,
        protocol_flag: bool,
        max_rev_share_bps: u256,
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
        self.max_rev_share_bps.write(3000_u256);
    }

    #[abi(embed_v0)]
    impl AdminImpl of IAdmin<ContractState> {
        fn add_fee_info(ref self: ContractState, suffix: felt252, fee_info: FeeInfo) {
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(suffix != PROHIBITED_SUFFIX, errors::PROHIBITED_SUFFIX);
            assert(fee_info.asset_addr.is_non_zero(), errors::FEE_ASSET_ZERO);
            assert(fee_info.flag == true, errors::FEE_FLAG_INVALID);
            assert(fee_info.rev_share_receiver.is_non_zero(), errors::ZERO_REV_SHARE_RECEIV);
            assert(
                fee_info.rev_share_bps <= self.max_rev_share_bps.read(), errors::INVALID_REV_BPS,
            );

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
                        rev_share_bps: fee_info.rev_share_bps,
                        rev_share_receiver: fee_info.rev_share_receiver,
                    },
                );
        }
        fn complete_add_fee_info(ref self: ContractState, suffix: felt252, fee_info: FeeInfo) {
            self.protocol_flag_check();
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
            self.protocol_flag_check();
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(addr.is_non_zero(), errors::ZERO_INPUT_ADDR);
            self.assert_is_admin();
            let suffix_count = self.suffix_log.read(suffix);
            assert(suffix_count == 0, errors::SUFFIX_ALREADY_REGISTERED);
            self.suffix_admin.write(suffix, addr);
            self
                .emit(
                    events::SuffixAdminEvent {
                        suffix: suffix, suffix_admin: addr, admin: get_caller_address(),
                    },
                );
        }

        fn add_fee_investor(ref self: ContractState, addr: ContractAddress) {
            assert(addr.is_non_zero(), errors::ZERO_INPUT_ADDR);
            self.assert_is_admin();
            self.fee_investor.write(addr);
        }

        fn update_protocol_flag(ref self: ContractState, flag: bool) {
            self.assert_is_admin();
            self.protocol_flag.write(flag);
        }

        fn update_rev_share_bps(ref self: ContractState, suffix: felt252, rev_share_bps: u256) {
            self.protocol_flag_check();
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            let suffix_admin = self.suffix_admin.read(suffix);
            assert(get_caller_address() == suffix_admin, errors::INVALID_SUFFIX_ADMIN);
            assert(rev_share_bps <= self.max_rev_share_bps.read(), errors::INVALID_REV_BPS);
            let suffix_log = self.suffix_log.read(suffix);
            assert(suffix_log == 1_u8, errors::SUFFIX_NOT_REG);

            let mut fee_info = self.fee_info.read(suffix);
            fee_info.rev_share_bps = rev_share_bps;
            self.fee_info.write(suffix, fee_info);
        }


        fn update_rev_share_receiver(
            ref self: ContractState, suffix: felt252, receiver: ContractAddress,
        ) {
            self.protocol_flag_check();
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            let suffix_admin = self.suffix_admin.read(suffix);
            assert(get_caller_address() == suffix_admin, errors::INVALID_SUFFIX_ADMIN);
            let suffix_log = self.suffix_log.read(suffix);
            assert(suffix_log == 1_u8, errors::SUFFIX_NOT_REG);

            let mut fee_info = self.fee_info.read(suffix);
            fee_info.rev_share_receiver = receiver;
            self.fee_info.write(suffix, fee_info);
        }
    }

    #[abi(embed_v0)]
    impl RegistryImpl of IRegistry<ContractState> {
        fn register(ref self: ContractState, name: felt252, suffix: felt252) {
            self.protocol_flag_check();
            assert(name.is_non_zero(), errors::ZERO_PREFIX);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            assert(suffix != PROHIBITED_SUFFIX, errors::PROHIBITED_SUFFIX);

            let suffix_log = self.suffix_log.read(suffix);
            assert(suffix_log == 1_u8, errors::SUFFIX_NOT_REG);

            self.not_registered(name, suffix);
            let caller = get_caller_address();
            let fee_struct = self.get_suffix_details(suffix);

            self.name_to_address.entry(suffix).write(name, caller);
            let count = self.address_name_count.entry(caller).entry(suffix).read();
            self.address_name_count.entry(caller).entry(suffix).write(count + 1);
            self.address_to_name.entry(caller).entry(suffix).write(count, name);
            self
                .suffix_mint_count
                .entry(suffix)
                .write(self.suffix_mint_count.entry(suffix).read() + 1);

            self.take_fees(caller, fee_struct);
            self
                .send_fees(
                    caller,
                    fee_struct.asset_addr,
                    fee_struct.rev_share_bps,
                    fee_struct.rev_share_receiver,
                );
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
        ) -> NameList {
            assert(addr.is_non_zero(), errors::ZERO_INPUT_ADDR);
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);

            let count = self.address_name_count.entry(addr).entry(suffix).read();
            let mut names: Array<felt252> = ArrayTrait::new();
            let mut index: u32 = 0;
            loop {
                if index >= count {
                    break;
                }
                names.append(self.address_to_name.entry(addr).entry(suffix).read(index));
                index += 1;
            }
            NameList { names, suffix }
        }

        fn get_suffix_fee_details(self: @ContractState, suffix: felt252) -> FeeInfo {
            self.fee_info.read(suffix)
        }

        fn gets_suffix_admin(self: @ContractState, suffix: felt252) -> ContractAddress {
            self.suffix_admin.read(suffix)
        }

        fn is_suffix_registered(self: @ContractState, suffix: felt252) -> bool {
            let suffix_log = self.suffix_log.read(suffix);
            if (suffix_log == 1_u8) {
                true
            } else {
                false
            }
        }
        fn get_suffix_mint_count(self: @ContractState, suffix: felt252) -> u64 {
            assert(suffix.is_non_zero(), errors::ZERO_SUFFIX);
            self.suffix_mint_count.read(suffix)
        }

        fn protocol_status(self: @ContractState) -> bool {
            self.protocol_flag.read()
        }
    }

    #[generate_trait]
    impl RegistryInternal of RegistryInternalTrait {
        fn not_registered(self: @ContractState, name: felt252, suffix: felt252) {
            let result = self.name_to_address.entry(suffix).read(name);
            assert(result.is_zero(), errors::ALREADY_REGISTERED_NAME);
        }

        fn get_suffix_details(self: @ContractState, suffix: felt252) -> FeeInfo {
            let fee_struct = self.fee_info.read(suffix);
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
            ref self: ContractState,
            receiver: ContractAddress,
            asset_addr: ContractAddress,
            rev_share: u256,
            rev_share_receiver: ContractAddress,
        ) {
            let dispatcher = IERC20Dispatcher { contract_address: asset_addr };
            let balance = dispatcher.balanceOf(get_contract_address());
            let fee_investor = self.fee_investor.read();
            if (balance > 0) {
                dispatcher.transfer(fee_investor, balance);
                IFeeInvestDispatcher { contract_address: fee_investor }
                    .deposit_fees(asset_addr, receiver, rev_share, rev_share_receiver);
            }
        }

        fn protocol_flag_check(self: @ContractState) {
            assert(self.protocol_flag.read(), errors::PROTOCOL_FLAG_FALSE);
        }

        fn assert_is_admin(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.admin.read(), errors::NOT_ADMIN);
        }
    }
}
