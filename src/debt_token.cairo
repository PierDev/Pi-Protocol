%lang starknet

// @title Pi debt token
// @author PieDev
// @notice used to represent a debt in the Pi ecosystem
// @dev implements some ERC20 methods but not all of them (not those for transfert)
// @dev can not be transfert: they represent a negative value...



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
    ERC20.initializer('Pi Debt USD', 'PiDb-USD', 18);
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

//
// External functions
//

// @notice Mint amount tokens to to_address
// @param to_address Address of the receiver
// @param amount Number of tokens to mint
// @return success (True if tokens are minted)
@external
func mint{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    to_address: felt, amount: Uint256
) -> (success: felt) {
    let (caller) = get_caller_address();
    let (pool_address) = _pool_address.read();
    with_attr error_message("debt_token::mint::must be called by the liquidity pool") {
        assert caller = pool_address ;
    }
    ERC20._mint(to_address, amount);
    return (TRUE,);
}

// @notice Burn amount tokens from to_address
// @param from_address Address where tokens are burn
// @param amount Number of tokens to burn
// @return success (True if tokens are burned)
@external
func burnFrom{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    from_address: felt, amount: Uint256
) -> (success: felt) {
    let (caller) = get_caller_address();
    let (pool_address) = _pool_address.read();
    with_attr error_message("debt_token::burn::must be called by the liquidity pool") {
        assert caller = pool_address ;
    }
    ERC20._burn(from_address, amount);
    return (TRUE,);
}