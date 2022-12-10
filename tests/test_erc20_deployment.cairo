%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256


@contract_interface
namespace IERC20 {
    func balanceOf(account: felt) -> (balance: Uint256) {
    }

    func totalSupply() -> (totalSupply: Uint256) {
    }
    
    func transfer(recipient: felt, amount: Uint256) -> (success: felt) {
    }

    func approve(spender: felt, amount: Uint256) -> (success: felt) {
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
namespace IPool {
    func deposit(amount: Uint256) -> (success: felt) {
    }

    func addCollateral(amount: Uint256) -> (success: felt) {
    }

    func borrow(amount: Uint256) -> (success: felt) {
    }

    func repay(amount: Uint256) -> (success: felt) {
    }

    func removeCollateral(amount: Uint256) -> (success: felt) {
    }

    func withdraw(amount: Uint256) -> (success: felt) {
    }

    func get_collateral_token() -> (collateral_token: felt) {
    }

    func get_lendable_token() -> (lendable_token: felt) {
    }

    func get_debt_token() -> (debt_token: felt) {
    }

    func get_ag_token() -> (ag_token: felt) {
    }

    func get_user_collateral(user: felt) -> (user_collateral: Uint256) {
    }

    func get_reserve_usage() -> (reserve_usage: Uint256) {
    }

    func get_current_rate() -> (rate: Uint256) {
    }

}

@external
func test_erc20{syscall_ptr: felt*, range_check_ptr}() {
    alloc_locals;

        %{  
        context.deployer_address = 12345678901234567890
        context.user_1_address = 987654321123456789
        context.user_2_address = 392838382882838401
        context.usdc_address = deploy_contract("src/erc20.cairo", [8583683267111105110, 85836867, 6, 1000000000000, 0, context.user_1_address]).contract_address
        context.eth_address = deploy_contract("src/erc20.cairo", [69116104101114101117109, 698472, 6, 10000000000000000000000000000000, 0, context.user_2_address]).contract_address
        context.oracle_address = deploy_contract("tests/oracle_test.cairo", []).contract_address
        context.agtoken_class_hash = declare("src/agToken.cairo").class_hash
        context.debt_token_class_hash = declare("src/debt_token.cairo").class_hash
        context.pool_address = deploy_contract("src/pool.cairo", [context.eth_address, context.usdc_address, context.debt_token_class_hash, context.agtoken_class_hash,context.oracle_address]).contract_address

    %}


    tempvar pool_address;
    tempvar eth_address;
    tempvar usdc_address;
    tempvar user_1_address;
    tempvar user_2_address;

    %{  
        ids.pool_address = context.pool_address 
        ids.eth_address = context.eth_address
        ids.usdc_address = context.usdc_address
        ids.user_1_address = context.user_1_address
        ids.user_2_address = context.user_2_address
    %}

    let (ag_token) = IPool.get_ag_token(contract_address = pool_address);
    let (debt_token) = IPool.get_debt_token(contract_address = pool_address);

    let amount_usdc_lended = Uint256(1000000000000, 0);
    let amount_eth_colateralized = Uint256(1000000000, 0);
    let amount_usdc_borrowed = Uint256(500000000000, 0);



    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.usdc_address) %}
        IERC20.approve(contract_address = usdc_address, spender = pool_address, amount = amount_usdc_lended);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.pool_address) %}
        IPool.deposit(contract_address = pool_address, amount = amount_usdc_lended);
    %{ stop_prank() %}
    let (ag_totalSupply) = IERC20.totalSupply(contract_address = ag_token);
    let (user_ag_balance) = IERC20.balanceOf(contract_address = ag_token, account = user_1_address);
    assert ag_totalSupply = Uint256(1000000000001000000, 0);
    assert user_ag_balance = Uint256(1000000000000000000, 0);

    %{ stop_prank = start_prank(ids.user_2_address, target_contract_address=ids.eth_address) %}
        IERC20.approve(contract_address = eth_address, spender = pool_address, amount = amount_eth_colateralized);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.user_2_address, target_contract_address=ids.pool_address) %}
        IPool.addCollateral(contract_address = pool_address, amount = amount_eth_colateralized);
        IPool.borrow(contract_address = pool_address, amount = amount_usdc_borrowed);
    %{ stop_prank() %}

    let (debt_totalSupply) = IERC20.totalSupply(contract_address = debt_token);
    let (user_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = user_2_address);
    let (user_2_usdc_balance) = IERC20.balanceOf(contract_address = usdc_address, account = user_2_address);
    assert debt_totalSupply = Uint256(500000000001000000, 0);
    assert user_debt_balance = Uint256(500000000000000000, 0);

    let (reserve_usage) = IPool.get_reserve_usage(contract_address = pool_address);
    let (current_rate) = IPool.get_current_rate(contract_address = pool_address);
    assert reserve_usage = Uint256(500000, 0);
    assert current_rate = Uint256(48888, 0);

    let (user_2_usdc_amount) = IERC20.balanceOf(contract_address = usdc_address, account = user_2_address);
    assert user_2_usdc_amount = Uint256(500000000000, 0);

    %{ stop_prank = start_prank(ids.user_2_address, target_contract_address=ids.usdc_address) %}
        IERC20.approve(contract_address = usdc_address, spender = pool_address, amount = user_2_usdc_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.user_2_address, target_contract_address=ids.pool_address) %}
        IPool.repay(contract_address = pool_address, amount = user_2_usdc_amount);
        IPool.removeCollateral(contract_address = pool_address, amount = amount_eth_colateralized);
    %{ stop_prank() %}

    let (debt_totalSupply) = IERC20.totalSupply(contract_address = debt_token);
    let (user_debt_balance) = IERC20.balanceOf(contract_address = debt_token, account = user_2_address);
    let (user_2_usdc_balance) = IERC20.balanceOf(contract_address = usdc_address, account = user_2_address);
    assert debt_totalSupply = Uint256(1000000, 0);
    assert user_debt_balance = Uint256(0, 0);
    let (user_2_usdc_amount) = IERC20.balanceOf(contract_address = usdc_address, account = user_2_address);
    assert user_2_usdc_amount = Uint256(1, 0);

    let (ag_amount) = IERC20.balanceOf(contract_address = ag_token, account = user_1_address);

    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.ag_token) %}
        IERC20.approve(contract_address = ag_token, spender = pool_address, amount = ag_amount);
    %{ stop_prank() %}

    %{ stop_prank = start_prank(ids.user_1_address, target_contract_address=ids.pool_address) %}
        IPool.withdraw(contract_address = pool_address, amount = ag_amount);
    %{ stop_prank() %}
    
    let (ag_totalSupply) = IERC20.totalSupply(contract_address = ag_token);
    let (user_ag_balance) = IERC20.balanceOf(contract_address = ag_token, account = user_1_address);
    assert ag_totalSupply = Uint256(1000000, 0);
    assert user_ag_balance = Uint256(0, 0);
    let (user_1_usdc_amount) = IERC20.balanceOf(contract_address = usdc_address, account = user_1_address);
    assert user_1_usdc_amount = Uint256(999999999999, 0);
    let (reserve_usage) = IPool.get_reserve_usage(contract_address = pool_address);
    let (current_rate) = IPool.get_current_rate(contract_address = pool_address);
    return ();
}