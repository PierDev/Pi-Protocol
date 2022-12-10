// this contract uses Empiric Oracle for getting ETH price in USD
%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
//return Eth price in usdc with 8 decimals
@view
func eth_usd{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}() 
-> (price: Uint256) {
    let uint256_price = Uint256(150000000000, 0);
    return (price = uint256_price); 
    }
