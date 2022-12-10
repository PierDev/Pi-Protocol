%lang starknet

// @title Pi pool
// @author PieDev
// @notice used to lend and borrow tokens

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import (
    assert_not_zero,
    assert_nn,
)
from starkware.cairo.common.math_cmp import is_le
from starkware.starknet.common.syscalls import (
    deploy,
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.uint256 import (
    Uint256,
    assert_uint256_le,
    assert_uint256_lt,
    uint256_unsigned_div_rem,
    uint256_check,
    uint256_eq,
    uint256_le,

)
from utils.math import (
    uint256_checked_add,
    uint256_checked_sub_le,
    uint256_checked_mul,
)


//
//  Constantes
//

const MIN_LIQUIDITY = 1000000;
const BURN_ADDRESS = 1;
const BORROW_RATIO = 1300000;         // 130% * MIN_LIQUIDITY
const LIQUIDATION_RATIO = 1150000;    // 115% * MIN_LIQUIDITY
const R_MIN = 10000; //1% * MIN_LIQUIDITY
const R_1 = 70000; //7% * MIN_LIQUIDITY
const R_2 = 600000; //60% * MIN_LIQUIDITY
const U_OPTI = 900000; //90% * MIN_LIQUIDITY
const YEAR_IN_SEC = 307584;
const ORACLE_DECIMALS = 100000000;
const USDC_DECIMALS = 1000000;
const ETH_DECIMALS = 1000000000000000000;


//
// Interfaces
//

@contract_interface
namespace IERC20 {
    func balanceOf(account: felt) -> (balance: Uint256) {
    }

    func totalSupply() -> (totalSupply: Uint256) {
    }
    
    func transfer(recipient: felt, amount: Uint256) -> (success: felt) {
    }

    func allowance(owner: felt, spender: felt) -> (remaining: Uint256) {
    }

    func transferFrom(sender: felt, recipient: felt, amount: Uint256) -> (success: felt) {
    }

    func mint(to_address: felt, amount: Uint256) -> (success: felt) {
    }

    func burnFrom(account: felt, amount: Uint256) -> (success: felt) {
    }
}

@contract_interface
namespace IOracle {
    func eth_usd() -> (price: Uint256) {
    }
}

//
// Storage vars
//

@storage_var
func _collateral_token() -> (res: felt) {
}

@storage_var
func _lendable_token() -> (res: felt) {
}

@storage_var
func _debt_token() -> (res: felt) {
}

@storage_var
func _pi_token() -> (res: felt) {
}

@storage_var
func _oracle() -> (res: felt) {
}

@storage_var
func _total_usdc_deposit() -> (res: Uint256) {
}

@storage_var
func _total_usdc_due() -> (res: Uint256) {
}


@storage_var
func _total_eth_deposit() -> (res: Uint256) {
}


@storage_var
func _user_collateral(user: felt) -> (res: Uint256) {
}

@storage_var
func _last_update_time() -> (res: felt) {
}

@storage_var
func _interest_rem() -> (res: Uint256) {
}




//
// Events
//

@event
func _debt_token_deployed(debt_token_address: felt) {
}

@event
func _pi_token_deployed(pi_token_address: felt) {
}

@event
func _oracle_deployed(oracle_address: felt) {
}

@event
func _emit_deposit(user: felt, amount: Uint256) {
}

@event
func _emit_addCollateral(user: felt, amount: Uint256) {
}

@event
func _emit_borrow(user: felt, amount: Uint256) {
}

@event
func _emit_repay(user: felt, amount: Uint256) {
}

@event
func _emit_removeCollateral(user: felt, amount: Uint256) {
}

@event
func _emit_withdraw(user: felt, amount: Uint256) {
}

@event
func _emit_liquidate(user: felt, amount: Uint256) {
}

@event
func _emit_update_debt(new_total_usdc_due:Uint256, new_total_usdc_deposit: Uint256) {
}

// @notice Contract Constructor
// @param collateral_token Address of collateral token
// @param lendable_token Address of lendable token
// @param debt_class_hash Class hash of debt tokens
// @param pi_class_hash Class hash of pi tokens
// @param oracle_address Class hash of interface with oracle
@constructor
func constructor{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
}(collateral_token: felt, lendable_token: felt, debt_class_hash: felt, pi_class_hash: felt, oracle_class_hash: felt) {
    with_attr error_message("Pool::constructor::all arguments must be non zero") {
        assert_not_zero(collateral_token);
        assert_not_zero(lendable_token);
    }
    _collateral_token.write(collateral_token);
    _lendable_token.write(lendable_token);

    let current_salt = 0;
    let (debt_token_address) = deploy(
        class_hash=debt_class_hash,
        contract_address_salt=current_salt,
        constructor_calldata_size=0,
        constructor_calldata=cast(new (), felt*),
        deploy_from_zero=FALSE,
    );
    _debt_token_deployed.emit(
        debt_token_address=debt_token_address
    );
    _debt_token.write(debt_token_address);

    let current_salt = 1;
    let (pi_token_address) = deploy(
        class_hash=pi_class_hash,
        contract_address_salt=current_salt,
        constructor_calldata_size=0,
        constructor_calldata=cast(new (), felt*),
        deploy_from_zero=FALSE,
    );
    _pi_token_deployed.emit(
        pi_token_address=pi_token_address
     );
     _pi_token.write(pi_token_address);


    let current_salt = 2;
    let (oracle_address) = deploy(
        class_hash=oracle_class_hash,
        contract_address_salt=current_salt,
        constructor_calldata_size=0,
        constructor_calldata=cast(new (), felt*),
        deploy_from_zero=FALSE,
    );
    _oracle_deployed.emit(
        oracle_address=oracle_address
    );
    _oracle.write(oracle_address);

    return ();
}


// @notice Deposit Function
// @param amount of token deposit
// @return success TRUE if ended.
// @dev mint pi_token for caller
// @dev transfert amount of lendable_token from caller to pool
@external
func deposit{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(amount: Uint256,
) -> (success: felt) {
    alloc_locals;
    uint256_check(amount);
    let (caller) = get_caller_address();
    let (self) = get_contract_address();
    let (lendable_token) = _lendable_token.read();
    let (allowance) = IERC20.allowance(contract_address = lendable_token, owner = caller, spender = self);
    with_attr error_message("Pool::deposit::allowance must be supperior than amount") {
        assert_uint256_le(amount, allowance);
    }

    let (pi_token) = _pi_token.read();
    let (pi_totalSupply) = IERC20.totalSupply(contract_address = pi_token);
    let (is_pi_totalSupply_eq_to_zero) = uint256_eq(pi_totalSupply, Uint256(0, 0));
    let min_liquidity_uint256 = Uint256(MIN_LIQUIDITY, 0);


    //first deposit ever
    if(is_pi_totalSupply_eq_to_zero == 1) {
        let (success) = IERC20.transferFrom(contract_address = lendable_token, sender = caller, recipient = self, amount = amount);
        IERC20.mint(contract_address = pi_token, to_address = BURN_ADDRESS, amount = min_liquidity_uint256);
        let (amount_mult_min_liquidity) = uint256_checked_mul(amount, min_liquidity_uint256);

        IERC20.mint(contract_address = pi_token, to_address = caller, amount = amount_mult_min_liquidity);

        _total_usdc_deposit.write(amount);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        updateDebt();
        let (total_reserve) = _total_usdc_deposit.read();
        let (success) = IERC20.transferFrom(contract_address = lendable_token, sender = caller, recipient = self, amount = amount);
        let (pi_totalSupply_mult_amount) = uint256_checked_mul(pi_totalSupply, amount);
        let (pi_to_mint, _) = uint256_unsigned_div_rem(pi_totalSupply_mult_amount, total_reserve);
        IERC20.mint(contract_address = pi_token, to_address = caller, amount = pi_to_mint);


        let (final_total_deposit) = uint256_checked_add(total_reserve, amount);
        _total_usdc_deposit.write(final_total_deposit);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }


    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    
    _emit_deposit.emit(
        user=caller,
        amount=amount
    );
    return (TRUE,);
}

// @notice Add Collateral Function
// @param amount of token deposit
// @return success TRUE if ended.
// @dev transfert amount of collateral_token from caller to pool
@external
func addCollateral{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(amount: Uint256,
) -> (success: felt) {
    alloc_locals;
    uint256_check(amount);
    let (caller) = get_caller_address();
    let (self) = get_contract_address();
    let (collateral_token) = _collateral_token.read();
    let (allowance) = IERC20.allowance(contract_address = collateral_token, owner = caller, spender = self);
    with_attr error_message("Pool::addCollateral::allowance must be supperior than amount") {
        assert_uint256_le(amount, allowance);
    }
    IERC20.transferFrom(contract_address = collateral_token, sender = caller, recipient = self, amount = amount);
    let (current_collateral) = _user_collateral.read(user = caller);
    let (final_collateral) = uint256_checked_add(amount, current_collateral);
    _user_collateral.write(user = caller, value = final_collateral);
    let (total_collateral) = _total_eth_deposit.read();
    let (final_total_collateral) = uint256_checked_add(amount, total_collateral);
    _total_eth_deposit.write(final_total_collateral);

    _emit_addCollateral.emit(
        user=caller,
        amount=amount
    );

    return (TRUE,);
}

// @notice borrow function
// @param amount of token to borrow
// @return success TRUE if ended
// @dev mint debt tokens for caller
// @dev transfert amount of lendable_token from pool to caller
@external
func borrow{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*, 
    range_check_ptr
}(amount: Uint256,
) -> (success: felt) {
    alloc_locals;
    uint256_check(amount);

    let (debt_token) = _debt_token.read();
    let (debt_totalSupply) = IERC20.totalSupply(contract_address = debt_token);
    let (is_debt_totalSupply_eq_to_zero) = uint256_eq(debt_totalSupply, Uint256(0, 0));
    if(is_debt_totalSupply_eq_to_zero == 1){
        let (current_date) = get_block_timestamp();
        _last_update_time.write(current_date);
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        updateDebt();
        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    let (user) = get_caller_address();
    let (self) = get_contract_address();
    let (collateral_token) = _collateral_token.read();

    let (total_borrowed) = _total_usdc_due.read();
    let (final_total_borrowed) = uint256_checked_add(total_borrowed, amount);
    let (total_deposit) = _total_usdc_deposit.read();
    with_attr error_message("Pool::borrow::Reserves are not sufficient") {
        assert_uint256_lt(final_total_borrowed, total_deposit);
    }

    let (user_collateral) = _user_collateral.read(user = user);
    let (user_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = user);
    let (usdc_due) = _compute_usdc_due(user_debt_balance, amount);

    let (ratio) = _compute_borrow_ratio(usdc_due, user_collateral);
    with_attr error_message("Pool::borrow::Ratio is too small to borrow ratio: {ratio}") {
        assert_uint256_lt(Uint256(BORROW_RATIO,0), ratio);
    }


    let (debt_totalSupply) = IERC20.totalSupply(contract_address = debt_token);
    let (is_debt_totalSupply_eq_to_zero) = uint256_eq(debt_totalSupply, Uint256(0, 0));
    let min_liquidity_uint256 = Uint256(MIN_LIQUIDITY, 0);

    if(is_debt_totalSupply_eq_to_zero == 1){
        //!TODO update usdc due
        IERC20.mint(contract_address = debt_token, to_address = BURN_ADDRESS, amount = min_liquidity_uint256);
        let (amount_mult_min_liquidity) = uint256_checked_mul(amount, min_liquidity_uint256);
        IERC20.mint(contract_address = debt_token, to_address = user, amount = amount_mult_min_liquidity);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;

    } else {
        let (debt_totalSupply_mult_amount) = uint256_checked_mul(debt_totalSupply, amount);
        let (debt_to_mint, _) = uint256_unsigned_div_rem(debt_totalSupply_mult_amount, total_borrowed);
        IERC20.mint(contract_address = debt_token, to_address = user, amount = debt_to_mint);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    let (lendable_token) = _lendable_token.read();
    IERC20.transfer(contract_address = lendable_token, recipient = user, amount = amount);
    _total_usdc_due.write(final_total_borrowed);

    _emit_borrow.emit(
        user=user,
        amount=amount
    );

    return (TRUE,);
}

// @notice repay function
// @param amount of token repaid
// @return success TRUE if ended
// @dev burn debt tokens from caller
// @dev transfert amount (or less) of lendable_token from caller to pool
@external
func repay{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(amount: Uint256,
) -> (success: felt) {
    alloc_locals;
    uint256_check(amount);
    let (caller) = get_caller_address();
    let (self) = get_contract_address();
    let (lendable_token) = _lendable_token.read();
    let (allowance) = IERC20.allowance(contract_address = lendable_token, owner = caller, spender = self);
    with_attr error_message("Pool::repay::allowance must be supperior than amount") {
        assert_uint256_le(amount, allowance);
    }

    updateDebt();
    let (debt_token) = _debt_token.read();
    let (caller_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = caller);
    let (caller_due) = _compute_usdc_due(caller_debt_balance, Uint256(0,0));
    let (total_usdc_due) = _total_usdc_due.read();

    let (amount_sup_due) = uint256_le(caller_due, amount);
    if(amount_sup_due == 1){
        IERC20.transferFrom(contract_address = lendable_token, sender = caller, recipient = self, amount = caller_due);
        IERC20.burnFrom(contract_address = debt_token, account = caller, amount = caller_debt_balance);
        let (new_total_usdc_due) = uint256_checked_sub_le(total_usdc_due, caller_due);
        _total_usdc_due.write(new_total_usdc_due);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (caller_debt_balance_mult_amount) = uint256_checked_mul(caller_debt_balance, amount);
        let (debt_to_burn, _) = uint256_unsigned_div_rem(caller_debt_balance_mult_amount, caller_due);
        IERC20.transferFrom(contract_address = lendable_token, sender = caller, recipient = self, amount = amount);
        IERC20.burnFrom(contract_address = debt_token, account = caller, amount = debt_to_burn);
        let (new_total_usdc_due) = uint256_checked_sub_le(total_usdc_due, amount);
        _total_usdc_due.write(new_total_usdc_due);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;


    _emit_repay.emit(
        user=caller,
        amount=amount
    );


    return (TRUE,);
}

// @notice removeCollateral function
// @param amount of collateral removed
// @return success TRUE if ended
// @dev transfert amount of collateral_token from pool to caller
@external
func removeCollateral{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(amount: Uint256,
) -> (success: felt) {
    alloc_locals;
    uint256_check(amount);
    let (caller) = get_caller_address();
    let (caller_collateral) = _user_collateral.read(user = caller);
    with_attr error_message("Pool::removeCollateral::amount must be inferrior than collateral") {
        assert_uint256_le(amount, caller_collateral);
    }

    updateDebt();
    let (debt_token) = _debt_token.read();
    let (caller_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = caller);
    let (usdc_due) = _compute_usdc_due(caller_debt_balance, Uint256(0,0));
    
    let (collateral_token) = _collateral_token.read();
    let (collateral_remining) = uint256_checked_sub_le(caller_collateral, amount);

    let(usdc_due_eq_zero) = uint256_eq(usdc_due, Uint256(0,0));
    if(usdc_due_eq_zero == 1) {
        IERC20.transfer(contract_address = collateral_token, recipient = caller, amount = amount);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (ratio_after) = _compute_borrow_ratio(usdc_due, collateral_remining);
        with_attr error_message("Pool::removeCollateral::ratio will be too small") {
            assert_uint256_le(Uint256(LIQUIDATION_RATIO, 0), ratio_after);
        }
        
        IERC20.transfer(contract_address = collateral_token, recipient = caller, amount = amount);

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }

    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;
    
    _user_collateral.write(user = caller, value = collateral_remining);


    _emit_removeCollateral.emit(
        user=caller,
        amount=amount
    );


    return(TRUE,);
}

// @notice withdraw function
// @param amount of pi_token removed
// @return success TRUE if ended
// @dev transfert amount of lendable_token from pool to caller
// @dev burn pi_token form caller
@external
func withdraw{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*, 
    range_check_ptr
}(amount: Uint256) -> (success: felt) {
    alloc_locals;
    uint256_check(amount);
    let (caller) = get_caller_address();
    let (pi_token) = _pi_token.read();
    let (caller_pi_balance) = IERC20.balanceOf(contract_address = pi_token, account = caller);
    with_attr error_message("Pool::withdraw::pi balance must be supperior or eq to amount") {
        assert_uint256_le(amount, caller_pi_balance);
    }

    //updateDebt();
    let (usdc_amount) = _compute_usdc_from_pi(amount);
    let (total_usdc_deposit) = _total_usdc_deposit.read();
    let (total_usdc_due) = _total_usdc_due.read();
    let (total_usdc_reming) = uint256_checked_sub_le(total_usdc_deposit, usdc_amount);
    let (final_reserve_usage) = _compute_reserve_usage(total_usdc_reming, total_usdc_due);
    with_attr error_message("Pool::withdraw::can not withdraw this amount: too much usdc are borrowed") {
        assert_uint256_le(final_reserve_usage, Uint256(MIN_LIQUIDITY,0));
    }
    
    
    let (lendable_token) = _lendable_token.read();
    IERC20.transfer(contract_address = lendable_token, recipient = caller, amount = usdc_amount);
    IERC20.burnFrom(contract_address = pi_token, account = caller, amount = amount);
    _total_usdc_deposit.write(total_usdc_reming);


    _emit_withdraw.emit(
        user=caller,
        amount=amount
    );


    return (TRUE,);
}



// @notice liquidate function
// @param user to liquidate
// @param amount of usdc send to liquidate
// @return success TRUE if ended
// @dev repay amount of user's dept and send some colateral to the caller
// @dev burn debt_token form user
@external
func liquidate{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*, 
    range_check_ptr
}(user: felt, amount: Uint256) -> (success: felt) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (self) = get_contract_address();
    let (lendable_token) = _lendable_token.read();
    let (allowance) = IERC20.allowance(contract_address = lendable_token, owner = caller, spender = self);
    with_attr error_message("Pool::liquidate::allowance must be supperior than amount") {
        assert_uint256_le(amount, allowance);
    }
    let (user_ratio) = get_user_ratio(user);
    with_attr error_message("Pool::liquidate::user ratio must be inferior than 1150000") {
        assert_uint256_le(user_ratio, Uint256(LIQUIDATION_RATIO, 0));
    }

    updateDebt();
    
    let (collateral_token) = _collateral_token.read();

    let (debt_token) = _debt_token.read();
    let (user_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = user);
    let (user_due) = _compute_usdc_due(user_debt_balance, Uint256(0,0));
    let (total_usdc_due) = _total_usdc_due.read();

    let (oracle) = _oracle.read();
    let (eth_price) = IOracle.eth_usd(contract_address = oracle);
    let (eth_price_mult_11) = uint256_checked_mul(eth_price, Uint256(11, 0));
    let (user_collateral) = _user_collateral.read(user);
    let (amount_sup_due) = uint256_le(user_due, amount);
    if(amount_sup_due == 1){
        IERC20.transferFrom(contract_address = lendable_token, sender = caller, recipient = self, amount = user_due);
        IERC20.burnFrom(contract_address = debt_token, account = user, amount = user_debt_balance);
        let (new_total_usdc_due) = uint256_checked_sub_le(total_usdc_due, user_due);
        _total_usdc_due.write(new_total_usdc_due);
        let (numerator) =  uint256_checked_mul(eth_price_mult_11, user_due);
        let (denominator) = uint256_checked_mul(Uint256(10, 0), Uint256(ORACLE_DECIMALS,0));
        let (eth_reward, _) = uint256_unsigned_div_rem(numerator, denominator);
        IERC20.transfer(contract_address = collateral_token, recipient = caller, amount = eth_reward);
        let (collateral_remining) = uint256_checked_sub_le(user_collateral, eth_reward);
        _user_collateral.write(user = user, value = collateral_remining); 

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        let (user_debt_balance_mult_amount) = uint256_checked_mul(user_debt_balance, amount);
        let (debt_to_burn, _) = uint256_unsigned_div_rem(user_debt_balance_mult_amount, user_due);
        IERC20.transferFrom(contract_address = lendable_token, sender = caller, recipient = self, amount = amount);
        IERC20.burnFrom(contract_address = debt_token, account = user, amount = debt_to_burn);
        let (new_total_usdc_due) = uint256_checked_sub_le(total_usdc_due, amount);
        _total_usdc_due.write(new_total_usdc_due);
        let (numerator) =  uint256_checked_mul(eth_price_mult_11, amount);
        let (denominator) = uint256_checked_mul(Uint256(10, 0), Uint256(ORACLE_DECIMALS,0));
        let (eth_reward, _) = uint256_unsigned_div_rem(numerator, denominator);
        IERC20.transfer(contract_address = collateral_token, recipient = caller, amount = eth_reward);
        let (collateral_remining) = uint256_checked_sub_le(user_collateral, eth_reward);
        _user_collateral.write(user = user, value = collateral_remining); 

        tempvar syscall_ptr = syscall_ptr;
        tempvar pedersen_ptr = pedersen_ptr;
        tempvar range_check_ptr = range_check_ptr;
    }
    local syscall_ptr: felt* = syscall_ptr;
    local pedersen_ptr: HashBuiltin* = pedersen_ptr;


    _emit_liquidate.emit(
        user=user,
        amount=amount
    );


    return (TRUE,);
}


// @notice updateDebt function
// @return success TRUE if ended
// @dev update total usdc_due in accordance of current_rate and time pass since last update
func updateDebt{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*, 
    range_check_ptr
}() -> (change: felt) {
    alloc_locals;
    let (last_update_time) = _last_update_time.read();
    let (current_time) = get_block_timestamp();

    let current_le_last_update = is_le(current_time, last_update_time);
    
    if(current_le_last_update == 1){
        return (FALSE,);
    } else {
        if(last_update_time == 0){
            return (FALSE,);
        } else {
            let (total_usdc_due) = _total_usdc_due.read();
            let (total_deposit) = _total_usdc_deposit.read();
            let (interest_rem) = _interest_rem.read();
            let (rate) = get_current_rate();
            let time_since_update = current_time - last_update_time;
            let (time_since_update_mult_rate) = uint256_checked_mul(Uint256(time_since_update, 0), rate);
            let (time_since_update_mult_rate_mult_usdc_due) = uint256_checked_mul(time_since_update_mult_rate, total_usdc_due);
            let (numerator) = uint256_checked_add(time_since_update_mult_rate_mult_usdc_due, interest_rem);
            let (denominator) = uint256_checked_mul(Uint256(YEAR_IN_SEC, 0), Uint256(MIN_LIQUIDITY, 0));
            let (interests, rem) = uint256_unsigned_div_rem(numerator, denominator);
            let (new_total_usdc_due) = uint256_checked_add(total_usdc_due, interests);
            let (new_total_usdc_deposit) = uint256_checked_add(total_deposit, interests);


            _last_update_time.write(current_time);
            _total_usdc_due.write(new_total_usdc_due);
            _total_usdc_deposit.write(new_total_usdc_deposit);
            _interest_rem.write(rem);
            _emit_update_debt.emit(
                new_total_usdc_due=new_total_usdc_due,
                new_total_usdc_deposit=new_total_usdc_deposit
            );

            return (TRUE,);
        }
    }
}

// @notice compute reserve usage
// @param deposit amount of lendable token deposit
// @param borrowed amount of lendable token borrowed
// @return borrowed*Min_liquidity/deposit
func _compute_reserve_usage{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(deposit: Uint256, borrowed: Uint256) -> (reserve_usage: Uint256) {
    alloc_locals;
    uint256_check(deposit);
    uint256_check(borrowed);
    let (MIN_LIQ_mult_borrowed) = uint256_checked_mul(borrowed, Uint256(MIN_LIQUIDITY, 0));
    let (reserve_usage, _) = uint256_unsigned_div_rem(MIN_LIQ_mult_borrowed, deposit);
    return (reserve_usage,);
}


// @notice compute usdc corresponding to an amount of pi_token
// @param pi_amount amount of pi_token
// @return corresponding
func _compute_usdc_from_pi{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(pi_amount: Uint256) -> (coresponding_usdc: Uint256) {
    alloc_locals;
    uint256_check(pi_amount);
    let (pi_token) = _pi_token.read();
    let (total_pi_supply) = IERC20.totalSupply(contract_address = pi_token);
    let (total_usdc) = _total_usdc_deposit.read();
    let (total_usdc_mult_pi_amount) = uint256_checked_mul(total_usdc, pi_amount);
    let (coresp, _) = uint256_unsigned_div_rem(total_usdc_mult_pi_amount, total_pi_supply);
    return (coresp,);
}


// @notice compute borrow ratio
// @param borrow_amount
// @param collateral_amount
// @return the ratio * minliquidity
func _compute_borrow_ratio{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(borrow_amount: Uint256, collateral_amount: Uint256) -> (ratio: Uint256) {
    alloc_locals;
    uint256_check(borrow_amount);
    uint256_check(collateral_amount);

    let min_liquidity_uint256 = Uint256(MIN_LIQUIDITY, 0);

    let (borrow_amount_is_zero) = uint256_eq(Uint256(0, 0), borrow_amount);
    if (borrow_amount_is_zero == 1) {
        return (min_liquidity_uint256,);
    }
    let (oracle) = _oracle.read();
    let (eth_price) = IOracle.eth_usd(contract_address = oracle);
    let (eth_price_mult_collateral_amount) = uint256_checked_mul(eth_price, collateral_amount);
    let (temp) = uint256_checked_mul(eth_price_mult_collateral_amount, Uint256(USDC_DECIMALS, 0));
    let (numerator) = uint256_checked_mul(temp, min_liquidity_uint256);
    
    let (temp2) = uint256_checked_mul(borrow_amount, Uint256(ORACLE_DECIMALS, 0));
    let (denominator) = uint256_checked_mul(temp2, Uint256(ETH_DECIMALS, 0));
    let (ratio, _) = uint256_unsigned_div_rem(numerator, denominator);

    return (ratio,);

}

// @notice return usdc due coresponding to an amount of debt_token and an amount of borrowed tokens
// @param amount_debt : the amount of debt_token
// @param amout_usdc_newly_borrowed
// @return usdc_due
func _compute_usdc_due{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*,
    range_check_ptr
}(amount_debt: Uint256, amout_usdc_newly_borrowed: Uint256) -> (usdc_due: Uint256) {
    alloc_locals;
    if ( amount_debt.high == 0 and amount_debt.low == 0){
        return (amout_usdc_newly_borrowed,);
    }
    let (debt_token) = _debt_token.read();
    let (total_debt_supply) = IERC20.totalSupply(contract_address = debt_token);
    let (total_usdc_due) = _total_usdc_due.read();
    let (amout_debt_mult_total_usdc_due) = uint256_checked_mul(amount_debt, total_usdc_due);
    let (usdc_due_from_debt, _) = uint256_unsigned_div_rem(amout_debt_mult_total_usdc_due, total_debt_supply);
    let (usdc_due) = uint256_checked_add(usdc_due_from_debt, amout_usdc_newly_borrowed);
    return (usdc_due,);
}


//
// Views
//

// @notice Address of the collateral
// @return collateral_token
@view
func get_collateral_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (collateral_token: felt) {
    let (collateral_token) = _collateral_token.read();
    return (collateral_token,);
}

// @notice Address of the lendable token
// @return lendable_token
@view
func get_lendable_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (lendable_token: felt) {
    let (lendable_token) = _lendable_token.read();
    return (lendable_token,);
}

// @notice Address of the dept token
// @return debt_token
@view
func get_debt_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (debt_token: felt) {
    let (debt_token) = _debt_token.read();
    return (debt_token,);
}

// @notice Address of the pi token
// @return pi_token
@view
func get_pi_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (pi_token: felt) {
    let (pi_token) = _pi_token.read();
    return (pi_token,);
}

// @notice Address of the oracle
// @return oracle
@view
func get_oracle{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (oracle: felt) {
    let (oracle) = _oracle.read();
    return (oracle,);
}



@view
func get_total_usdc_deposit {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (total_usdc_deposit: Uint256) {
    let (total_usdc_deposit) = _total_usdc_deposit.read();
    return (total_usdc_deposit,);
}


@view 
func get_total_usdc_due {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (total_usdc_due: Uint256) {
    let (total_usdc_due) = _total_usdc_due.read();
    return (total_usdc_due,);
}


@view
func get_rem{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (rem: Uint256) {
    let (rem) = _interest_rem.read();
    return (rem,);
}


@view
func get_current_rate{
    syscall_ptr: felt*, 
    pedersen_ptr: HashBuiltin*, 
    range_check_ptr
}() -> (rate: Uint256) {
    alloc_locals;
    let (reserve_usage) = get_reserve_usage();
    let uint_u_opti = Uint256(U_OPTI, 0);
    let (usage_inf_optimal) = uint256_le(reserve_usage, uint_u_opti);
    let uint_r_min = Uint256(R_MIN, 0);
    let uint_r_1 = Uint256(R_1, 0);
    
    if(usage_inf_optimal == 1){
        let (r_1_mult_reserve_usage) = uint256_checked_mul(uint_r_1, reserve_usage);
        let (r_1_mult_reserve_usage_div_u_opti, _) = uint256_unsigned_div_rem(r_1_mult_reserve_usage, uint_u_opti);
        let (rate) = uint256_checked_add(r_1_mult_reserve_usage_div_u_opti, uint_r_min);
        return (rate,);
    } else {
        let (reserve_usage_minus_u_opti) = uint256_checked_sub_le(reserve_usage, uint_u_opti);
        let (reserve_usage_minus_u_opti_mult_r_2) = uint256_checked_mul(reserve_usage_minus_u_opti, Uint256(R_2, 0));
        let (denominator) = uint256_checked_sub_le(Uint256(MIN_LIQUIDITY, 0), uint_u_opti);
        let (var_rate, _) = uint256_unsigned_div_rem(reserve_usage_minus_u_opti_mult_r_2, denominator);
        let (fixe_rate) = uint256_checked_add(uint_r_min, uint_r_1);
        let (rate) = uint256_checked_add(var_rate, fixe_rate);
        return (rate,);
    }
}


// @notice Amount of collateral of gift user
// @return user_collateral
@view
func get_user_collateral {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (user_collateral: Uint256) {
    let (user_collateral) = _user_collateral.read(user = user);
    return (user_collateral,);
}

// @notice Usage of reserve 
// @return reserve_usage
// @dev total_borrowed/total_deposit * MIN_LIQUIDITY
@view
func get_reserve_usage {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (reserve_usage: Uint256) {
    let (total_usdc_deposit) = _total_usdc_deposit.read();
    let (total_usdc_due) = _total_usdc_due.read();
    let (reserve_usage) = _compute_reserve_usage(total_usdc_deposit, total_usdc_due);
    return (reserve_usage,);
}

// @notice value of user deposit 
// @return deposit_value
@view
func get_user_deposit_value {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (user_deposit_value: Uint256) {
    let (pi_token) = _pi_token.read();
    let (user_pi_balance) = IERC20.balanceOf(contract_address = pi_token, account = user);
    let (deposit_value) = _compute_usdc_from_pi(user_pi_balance);
    return (deposit_value,);
}



// @notice value of user debt 
// @return debt_value
@view
func get_user_debt_value {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (user_deposit_value: Uint256) {
    let (debt_token) = _debt_token.read();
    let (user_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = user);
    let (debt_value) = _compute_usdc_due(user_debt_balance, Uint256(0,0));
    return (debt_value,);
}

// @notice ratio of user  
// @return user_ratio
@view
func get_user_ratio {syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user: felt) -> (user_ratio: Uint256) {
    let (borrow_amount) = get_user_debt_value(user);
    let (collateral_amount) = _user_collateral.read(user = user);
    let (user_ratio) = _compute_borrow_ratio(borrow_amount, collateral_amount);
    return (user_ratio,);
}


