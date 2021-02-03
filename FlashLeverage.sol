// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import { IERC20 } from "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/math/SafeMath.sol";
import { SafeERC20 } from "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v3.3.0/contracts/token/ERC20/SafeERC20.sol";

import { IFlashLoanReceiver } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import { ILendingPoolAddressesProvider } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import { ILendingPool } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/interfaces/ILendingPool.sol";
import { IWETHGateway } from "https://raw.githubusercontent.com/aave/protocol-v2/ice/mainnet-deployment-03-12-2020/contracts/misc/interfaces/IWETHGateway.sol";
import { IAToken } from "https://raw.githubusercontent.com/aave/protocol-v2/ice/mainnet-deployment-03-12-2020/contracts/interfaces/IAToken.sol";
import { ICreditDelegationToken } from "https://raw.githubusercontent.com/aave/protocol-v2/master/contracts/interfaces/ICreditDelegationToken.sol";

import { IUniswapV2Router02 } from "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";

contract FlashLoanArbitrageur is IFlashLoanReceiver {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    enum CallbackMethod {
        Open,
        Close
    }
    
    // Kovan adresses
    // address internal constant DAI_CONTRACT = 0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD;
    // address internal constant WETH_CONTRACT = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    // address internal constant AWETH_CONTRACT = 0x87b1f4cf9BD63f7BBD3eE1aD04E8F52540349347;
    // address internal constant AAVE_CONTRACT = 0x88757f2f99175387aB4C6a4b3067c77A695b0349;
    // address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // address internal constant WETH_GATEWAY_ADDRESS = 0xf8aC10E65F2073460aAD5f28E1EABE807DC287CF;
    
    // Mainnet
    address internal constant DAI_CONTRACT = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant DEBT_DAI_CONTRACT = 0x6C3c78838c761c6Ac7bE9F59fe808ea2A6E4379d;
    address internal constant WETH_CONTRACT = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AWETH_CONTRACT = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
    address internal constant AAVE_CONTRACT = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5;
    address internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH_GATEWAY_ADDRESS = 0xDcD33426BA191383f1c9B431A342498fdac73488;
    
    ILendingPoolAddressesProvider public override ADDRESSES_PROVIDER;
    ILendingPool public override LENDING_POOL;
    IWETHGateway public WETH_GATEWAY;

    IUniswapV2Router02 public UNISWAP_ROUTER;
    
    // constructor(ILendingPoolAddressesProvider provider) public {
    //     ADDRESSES_PROVIDER = provider;
    //     LENDING_POOL = ILendingPool(provider.getLendingPool());
    // }
    
    constructor() public {
        ADDRESSES_PROVIDER = ILendingPoolAddressesProvider(AAVE_CONTRACT);
        LENDING_POOL = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());
        WETH_GATEWAY = IWETHGateway(WETH_GATEWAY_ADDRESS);
        UNISWAP_ROUTER = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);
    }

    receive() external payable {
    }

    function swapERC20ForETH(address token, uint amountIn, uint amountOutMin) internal returns (uint swapReturns) {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = UNISWAP_ROUTER.WETH();
    
        uint deadline = block.timestamp + 15; // Pass this as argument
        
        IERC20(token).safeApprove(address(UNISWAP_ROUTER), amountIn);
        
        swapReturns = UNISWAP_ROUTER.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), deadline)[0];
        
        require(swapReturns > 0, "Uniswap didn't return anything");
    }

    // Convert the user funds and flashloan to ETH 
    // Deposit the ETH to AAVE 
    // Borrow the flashloan amount from AAVE 
    // Repay the flashloan 
    function executeOperation(
        address[] calldata assets,
        uint[] calldata amounts,
        uint[] calldata premiums,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {
        (address sender, CallbackMethod method) = abi.decode(params, (address, CallbackMethod));
        
        uint amountOwing = amounts[0].add(premiums[0]);

        if(method == CallbackMethod.Open) {
            uint amountOutMin = 0; // TODO: Pass this as argument
            swapERC20ForETH(assets[0], IERC20(DAI_CONTRACT).balanceOf(address(this)), amountOutMin);

            // Deposit ETH to AAVE

            require(address(this).balance > 0, "Uniswap did not return ETH");
            WETH_GATEWAY.depositETH{ value: address(this).balance }(sender, 0);
            // LENDING_POOL.deposit(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE), address(this).balance, address(this), 0);

            // Do something with the aWETH
            require(IERC20(AWETH_CONTRACT).balanceOf(sender) > 0, "Did not receive any A token");
            // require(IERC20(AWETH_CONTRACT).balanceOf(address(this)) != 0, "Didn't receive any a token");

            // Borrow amountOwing DAI and repay the loan

            require(ICreditDelegationToken(DEBT_DAI_CONTRACT).borrowAllowance(sender, address(this)) >= amountOwing, "Not enough allowance to borrow");
            LENDING_POOL.borrow(DAI_CONTRACT, amountOwing, 2, 0, sender);

            require(IERC20(DAI_CONTRACT).balanceOf(address(this)) >= amountOwing, "Not enough funds to repay");
        } else if (method == CallbackMethod.Close) {
            // Repay the debt using the FlashLoan
            
            IERC20(assets[0]).safeApprove(address(LENDING_POOL), amounts[0]);
            LENDING_POOL.repay(assets[0], amounts[0], 2, sender);

            // Swap aToken for flashloaned token

            address[] memory path = new address[](2);
            path[0] = UNISWAP_ROUTER.WETH();
            path[1] = assets[0];

            uint swapInput = UNISWAP_ROUTER.getAmountsIn(amountOwing, path)[0]; // How much aToken to swap to repay the FlashLoan

            IERC20(AWETH_CONTRACT).transferFrom(sender, address(this), swapInput); // Get user aTokens
            
            uint aWETHBalance = IERC20(AWETH_CONTRACT).balanceOf(address(this));
            
            require(aWETHBalance > 0, "No aWETH tokens");
            
            require(swapInput <= aWETHBalance, "Not enough aWETH to repay FlashLoan");

            LENDING_POOL.withdraw(path[0], type(uint256).max, address(this)); // Maybe swap directly with 1inch to simplify
            
            require(IERC20(AWETH_CONTRACT).balanceOf(address(this)) == 0, "aWETH where not burned");
            
            require(swapInput <= IERC20(path[0]).balanceOf(address(this)), "Not enough WETH to repay FlashLoan");

            IERC20(path[0]).safeApprove(address(UNISWAP_ROUTER), IERC20(path[0]).balanceOf(address(this)));
            uint deadline = block.timestamp + 15; // Pass this as argument
            UNISWAP_ROUTER.swapTokensForExactTokens(amountOwing, type(uint256).max, path, address(this), deadline)[0];
        } else {
            revert("Wrong FlashLoan callback method");
        }

        IERC20(assets[0]).safeApprove(address(LENDING_POOL), amountOwing);

        return true;
    }

    // Amount is user funds (ex: $1k)
    // Ask for a flashloan of 2x the amount
    function open(uint amount) public {
        require(amount > 0, "amount must be greater than zero");
        
        IERC20(DAI_CONTRACT).safeTransferFrom(msg.sender, address(this), amount); // Get user funds
        
        address receiverAddress = address(this);

        address[] memory assets = new address[](1);
        assets[0] = DAI_CONTRACT;

        uint[] memory amounts = new uint[](1);
        amounts[0] = amount.mul(2); // Maybe as input for leverage multiplicator

        // 0 = no debt, 1 = stable, 2 = variable
        uint[] memory modes = new uint[](1);
        modes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = abi.encode(msg.sender, CallbackMethod.Open);
        uint16 referralCode = 0;

        LENDING_POOL.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }
    
    function close(uint amount) public {
        require(IERC20(AWETH_CONTRACT).balanceOf(msg.sender) > 0, "Must have collateral");
        require(IERC20(DEBT_DAI_CONTRACT).balanceOf(msg.sender) > 0, "Must have debt");
        
        address receiverAddress = address(this);
        
        address[] memory assets = new address[](1);
        assets[0] = DAI_CONTRACT;

        uint[] memory amounts = new uint[](1);
        amounts[0] = amount;

        // 0 = no debt, 1 = stable, 2 = variable
        uint[] memory modes = new uint[](1);
        modes[0] = 0;

        address onBehalfOf = address(this);
        bytes memory params = abi.encode(msg.sender, CallbackMethod.Close);
        uint16 referralCode = 0;

        LENDING_POOL.flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
    }
}
