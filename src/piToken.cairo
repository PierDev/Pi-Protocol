%lang starknet

// @title Pi token
// @author PieDev
// @notice used to represent a deposit in the Pi ecosystem
// @dev implements some ERC20 methods but not all of them (not those for transfert)
// @dev represent a part of the vault contening deposits and interests



from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (
    Uint256,
)
from starkware.cairo.common.math import (
    assert_not_zero,
)
from starkware.starknet.common.syscalls import (
    get_caller_address,
)
// Lib to create and monitore ERC20
from openzeppelin.token.erc20.library import ERC20

//
// Storage Vars
//

@storage_var
func _pool_address() -> (res: felt) {
}


// @notice Contract Constructor
@constructor
func constructor{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
}() {
    let (pool_address) = get_caller_address();
    _pool_address.write(pool_address);
    ERC20.initializer('Pi USDC', 'PI-USDC', 8);
    return ();
}



//
// View
//

// @notice Address of the pool who emit the dept
// @return pool_address
@view 
func pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (pool_address: felt) {
    let (pool_address) = _pool_address.read();
    return (pool_address,);
}


//
// View ERC-20
//

// @notice Name of the token
// @return name
@view
func name{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (name: felt) {
    let (name) = ERC20.name();
    return (name,);
}

// @notice Symbol of the token
// @return symbol
func symbol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (symbol: felt) {
    let (symbol) = ERC20.symbol();
    return (symbol,);
}

// @notice Total supply of the token
// @return the totalSupply
@view
func totalSupply{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    totalSupply: Uint256
) {
    let (totalSupply: Uint256) = ERC20.total_supply();
    return (totalSupply,);
}

// @notice Decimals of the token
// @return decimals
@view
func decimals{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    decimals: felt
) {
    let (decimals) = ERC20.decimals();
    return (decimals,);
}

// @notice Balance of 'account'
// @param account Accout address whose balance is fetched
// @return balance Balance of 'account'
@view
func balanceOf{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(account: felt) -> (
    balance: Uint256
) {
    let (balance: Uint256) = ERC20.balance_of(account);
    return (balance,);
}

// @notice Allowance of 'spender' on 'owner'
// @param owner Account address on which the allowance is fetched
// @param spender Account address which has the allowance
// @return allowance Allowance of 'spender' on 'owner'
@view
func allowance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (owner: felt, spender: felt) -> (
    remaining: Uint256
){
    let (remaining: Uint256) = ERC20.allowance(owner, spender);
    return (remaining,);
}

//
// External functions
//


// @notice Transfer `amount` tokens from `caller` to `recipient`
// @param recipient Account address to which tokens are transferred
// @param amount Amount of tokens to transfer
// @return success 0 or 1
@external
func transfer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt, amount: Uint256
) -> (success: felt) {
    ERC20.transfer(recipient, amount);
    return(TRUE,);
}

// @notice Transfer `amount` tokens from `sender` to `recipient`
// @dev Checks for allowance.
// @param sender Account address from which tokens are transferred
// @param recipient Account address to which tokens are transferred
// @param amount Amount of tokens to transfer
// @return success 0 or 1
@external
func transferFrom{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    sender: felt, recipient: felt, amount: Uint256
) -> (success: felt) {
    ERC20.transfer_from(sender, recipient, amount);
    return (TRUE,);
}

// @notice Approve `spender` to transfer `amount` tokens on behalf of `caller`
// @param spender The address which will spend the funds
// @param amount The amount of tokens to be spent
// @return success 0 or 1
@external
func approve{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    spender: felt, amount: Uint256
) -> (success: felt) {
    ERC20.approve(spender, amount);
    return (TRUE,);
}

// @notice Increase allowance of `spender` to transfer `added_value` more tokens on behalf of `caller`
// @param spender The address which will spend the funds
// @param added_value The increased amount of tokens to be spent
// @return success 0 or 1
@external
func increaseAllowance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    spender: felt, added_value: Uint256
) -> (success: felt) {
    ERC20.increase_allowance(spender, added_value);
    return (TRUE,);
}

// @notice Decrease allowance of `spender` to transfer `subtracted_value` less tokens on behalf of `caller`
// @param spender The address which will spend the funds
// @param subtracted_value The decreased amount of tokens to be spent
// @return success 0 or 1
@external
func decreaseAllowance{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    spender: felt, subtracted_value: Uint256
) -> (success: felt) {
    ERC20.decrease_allowance(spender, subtracted_value);
    return (TRUE,);
}

// @notice Mint amount tokens to to_address
// @param to_address Address of the receiver
// @param amount Number of tokens to mint
// @return success  0 or 1
@external
func mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    to_address: felt, amount: Uint256
) -> (success: felt) {
    let (caller) = get_caller_address();
    let (pool_address) = _pool_address.read();
    with_attr error_message("pi_token::mint::must be called by the liquidity pool") {
        assert caller = pool_address ;
    }
    ERC20._mint(to_address, amount);
    return (TRUE,);
}

// @notice Burn amount tokens from to_address
// @param from_address Address where tokens are burn
// @param amount Number of tokens to burn
// @return success  0 or 1
@external
func burnFrom{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    from_address: felt, amount: Uint256
) -> (success: felt) {
    let (caller) = get_caller_address();
    let (pool_address) = _pool_address.read();
    with_attr error_message("pi_token::burn::must be called by the liquidity pool") {
        assert caller = pool_address ;
    }
    ERC20._burn(from_address, amount);
    return (TRUE,);
}