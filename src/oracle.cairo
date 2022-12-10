// this contract uses Empiric Oracle for getting ETH price in USD
%lang starknet

from starkware.cairo.common.uint256 import (
    split_64,
    Uint256,
)
from starkware.cairo.common.math import (
    unsigned_div_rem,
)
from starkware.cairo.common.math_cmp import (
    is_le,
)

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc

// Oracle Interface Definition
const ORACLE_PROXY_ADDRESS = 0x446812bac98c08190dee8967180f4e3cdcd1db9373ca269904acb17f67f7093;
const KEY_ETH = 19514442401534788;  // str_to_felt("eth/usd")


// Empiric Oracle contract interface
@contract_interface
namespace IEmpiricOracle {
    func get_spot_median(pair_id: felt) -> (
        price: felt, decimals: felt, last_updated_timestamp: felt, num_sources_aggregated: felt) {
    }
}

func to_18_decimals{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}(price, decimals) 
->(price: felt, decimals: felt) {
    if (decimals == 8){
        return (price, decimals);
    } else {
        if (is_le(decimals, 8) == 1){
            let (price, _) = unsigned_div_rem(price, 10);
            return to_18_decimals(price, decimals-1);
        } else {
            return to_18_decimals(price * 10, decimals+1);
        }
    }
}


//return Eth price in usdc with 8 decimals
@view
func eth_usd{
    syscall_ptr : felt*,
    pedersen_ptr : HashBuiltin*,
    range_check_ptr
}() 
-> (price: Uint256) {
    let (eth_price,
        eth_decimals,
        last_updated_timestamp,
        num_sources_aggregated) = IEmpiricOracle.get_spot_median(
            contract_address = ORACLE_PROXY_ADDRESS, pair_id = KEY_ETH
        );
    let (price, _) = to_18_decimals(eth_price, eth_decimals); 
    let uint256_price = Uint256(price, 0);
    return (price = uint256_price); 
    }
