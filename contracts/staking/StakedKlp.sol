// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/IKlpManager.sol";

import "./interfaces/IRewardTracker.sol";

contract StakedKlp {
    using SafeMath for uint256;

    string public constant name = "StakedKlp";
    string public constant symbol = "sKLP";
    uint8 public constant decimals = 18;

    address public klp;
    IKlpManager public klpManager;
    address public feeKlpTracker;

    mapping (address => mapping (address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _klp,
        IKlpManager _klpManager,
        address _feeKlpTracker
    ) public {
        klp = _klp;
        klpManager = _klpManager;
        feeKlpTracker = _feeKlpTracker;
    }

    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedKlp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return IRewardTracker(feeKlpTracker).depositBalances(_account, klp);
    }

    function totalSupply() external view returns (uint256) {
        return IERC20(feeKlpTracker).totalSupply();
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "StakedKlp: approve from the zero address");
        require(_spender != address(0), "StakedKlp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "StakedKlp: transfer from the zero address");
        require(_recipient != address(0), "StakedKlp: transfer to the zero address");

        require(
            klpManager.lastAddedAt(_sender).add(klpManager.cooldownDuration()) <= block.timestamp,
            "StakedKlp: cooldown duration not yet passed"
        );
        IRewardTracker(feeKlpTracker).unstakeForAccount(_sender, klp, _amount, _sender);
        IRewardTracker(feeKlpTracker).stakeForAccount(_sender, _recipient, klp, _amount);
    }


}
