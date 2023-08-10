// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IKlpManager.sol";
import "../access/Governable.sol";
import "./../core/interfaces/IVault.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    address public immutable weth;

    address public immutable klp; 

    address public immutable feeKlpTracker;

    address public immutable klpManager;

    IVault public immutable vault;

    mapping(address => address) public pendingReceivers;

    event StakeKlp(address indexed account, uint256 amount);
    event UnstakeKlp(address indexed account, uint256 amount);
    event StakeMigration(address indexed account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    constructor(
        address _weth,
        address _klp,
        address _vault,
        address _feeKlpTracker,
        address _klpManager
    ) public{
        weth = _weth;
        klp = _klp;
        vault = IVault(_vault);    

        feeKlpTracker = _feeKlpTracker;

        klpManager = _klpManager;

    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function mintAndStakeKlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) external nonReentrant returns (uint256) {
        require(_amount != 0, "RewardRouter: invalid _amount");

        return _mintAndStakeKlp(msg.sender,msg.sender,_token, _amount, _minUsdk, _minKlp);
    }

    function _mintAndStakeKlp(
        address fundingAccount,
        address account,
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) private returns (uint256) {

        uint256 klpAmount = IKlpManager(klpManager).addLiquidityForAccount(fundingAccount, account, _token, _amount, _minUsdk, _minKlp);
        IRewardTracker(feeKlpTracker).stakeForAccount(account, account, klp, klpAmount);

        emit StakeKlp(account, klpAmount);

        return klpAmount;
    }


    function mintAndStakeKlpETH(uint256 _minUsdk, uint256 _minKlp) external payable nonReentrant returns (uint256) {
        require(msg.value != 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        return _mintAndStakeKlpETH(msg.value,_minUsdk, _minKlp);
    }

    
    function _mintAndStakeKlpETH(uint256 _amount,uint256 _minUsdk, uint256 _minKlp) private returns (uint256) {
        require(_amount != 0, "RewardRouter: invalid _amount");

        IERC20(weth).approve(klpManager, _amount);

        address account = msg.sender;
        uint256 klpAmount = IKlpManager(klpManager).addLiquidityForAccount(address(this), account, weth, _amount, _minUsdk, _minKlp);

        IRewardTracker(feeKlpTracker).stakeForAccount(account, account, klp, klpAmount);

        emit StakeKlp(account, klpAmount);

        return klpAmount;
    }

    function unstakeAndRedeemKlp(
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_klpAmount != 0, "RewardRouter: invalid _klpAmount");

        address account = msg.sender;
        IRewardTracker(feeKlpTracker).unstakeForAccount(account, klp, _klpAmount, account);
        uint256 amountOut = IKlpManager(klpManager).removeLiquidityForAccount(account, _tokenOut, _klpAmount, _minOut, _receiver);

        emit UnstakeKlp(account, _klpAmount);

        return amountOut;
    }

    function unstakeAndRedeemKlpETH(
        uint256 _klpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_klpAmount != 0, "RewardRouter: invalid _klpAmount");

        address account = msg.sender;
        IRewardTracker(feeKlpTracker).unstakeForAccount(account, klp, _klpAmount, account);
        uint256 amountOut = IKlpManager(klpManager).removeLiquidityForAccount(account, weth, _klpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeKlp(account, _klpAmount);

        return amountOut;
    }

    function claim(address _rewardToken, bool _shouldAddIntoKLP, bool withdrawEth) external nonReentrant {
        require(IRewardTracker(feeKlpTracker).allTokens(_rewardToken), "RewardRouter: invalid _rewardToken");
        address account = msg.sender;
        if(_shouldAddIntoKLP && vault.whitelistedTokens(_rewardToken)){ 
            uint256 amount = IRewardTracker(feeKlpTracker).claimForAccount(account, _rewardToken, address(this));
            if(amount > 0){
                if(_rewardToken == weth){
                    _mintAndStakeKlpETH(amount,0,0);
                }else{
                    IERC20(_rewardToken).approve(klpManager, amount);
                    _mintAndStakeKlp(address(this),account,_rewardToken,amount,0,0);
                }
            }   
        }else if(withdrawEth && _rewardToken == weth){
            uint256 amount = IRewardTracker(feeKlpTracker).claimForAccount(account, _rewardToken, address(this));
            if(amount > 0){
                IWETH(weth).withdraw(amount);
                payable(account).sendValue(amount);
            }
        }else{
            IRewardTracker(feeKlpTracker).claimForAccount(account, _rewardToken, account);
        }
    }

    function handleRewards(
        bool _shouldConvertWethToEth,
        bool _shouldAddIntoKLP
    ) external nonReentrant {
        address account = msg.sender;
        if (_shouldConvertWethToEth || _shouldAddIntoKLP ) {
            (address[] memory tokens,uint256[] memory amounts) = IRewardTracker(feeKlpTracker).claimAllForAccount(account, address(this));
            for (uint256 i = 0; i < tokens.length; i++) {
                address token = tokens[i];
                uint256 amount = amounts[i];
                if(amount > 0){
                    if(_shouldAddIntoKLP && vault.whitelistedTokens(token)){ 
                        if(token == weth){
                            _mintAndStakeKlpETH(amount,0,0);
                        }else{
                            IERC20(token).approve(klpManager, amount);
                            _mintAndStakeKlp(address(this),account,token,amount,0,0);
                        }
                    }else if(_shouldConvertWethToEth && token == weth ){
                        IWETH(weth).withdraw(amount);
                        payable(account).sendValue(amount);
                    }else{
                        IERC20(token).safeTransfer(account, amount);
                    }    
                }         
            }    
        } else {
            IRewardTracker(feeKlpTracker).claimAllForAccount(account, account);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        require(
            IKlpManager(klpManager).lastAddedAt(_sender).add(IKlpManager(klpManager).cooldownDuration()) <= block.timestamp,
            "RewardRouter: cooldown duration not yet passed"
        );

        delete pendingReceivers[_sender];

        uint256 klpAmount = IRewardTracker(feeKlpTracker).depositBalances(_sender, klp);
        if (klpAmount > 0) {
            IRewardTracker(feeKlpTracker).unstakeForAccount(_sender, klp, klpAmount, _sender);
            IRewardTracker(feeKlpTracker).stakeForAccount(_sender, receiver, klp, klpAmount);
        }
    }

}
