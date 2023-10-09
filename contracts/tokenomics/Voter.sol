// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.13;

import "./libraries/Math.sol";
import "./interfaces/IBribe.sol";
import "./interfaces/IBribeFactory.sol";
import "./interfaces/IV2Factory.sol";
import "./interfaces/IV3Factory.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";

contract Voter is IVoter {
    enum PoolType {
        V2_POOL,
        V3_POOL,
        EXTERNAL_POOL
    }

    address public immutable _ve; // the ve token that governs these contracts
    address public immutable bribeFactory;
    address public immutable v2Factory;
    address public immutable v3Factory;
    uint internal constant DURATION = 7 days; // rewards are released over 7 days
    address public governor; // should be set to an IGovernor
    address public emergencyCouncil; // credibly neutral party similar to Curve's Emergency DAO

    uint public totalWeight; // total voting weight

    address[] public pools; // all pools viable for incentives
    mapping(address => address) public external_bribes; // pool => external bribe (real bribes)
    mapping(address => PoolType) public poolTypes; // pool => poolTypes
    mapping(address => uint256) public weights; // pool => weight
    mapping(uint => mapping(address => uint256)) public votes; // nft => pool => votes
    mapping(uint => address[]) public poolVote; // nft => pools
    mapping(uint => uint) public usedWeights;  // nft => total voting weight of user
    mapping(uint => uint) public lastVoted; // nft => timestamp of last vote, to ensure one vote per epoch
    mapping(address => bool) public isVoteable;
    mapping(address => bool) public isWhitelisted;

    event VoteablePoolAdded(address creator, address indexed external_bribe, address indexed pool);
    event VoteablePoolRemoved(address indexed pool);
    event Voted(address indexed voter, uint tokenId, uint256 weight);
    event Abstained(uint tokenId, uint256 weight);
    event Whitelisted(address indexed whitelister, address indexed token);

    constructor(address __ve, address _bribes, address _v2Factory, address _v3Factory) {
        _ve = __ve;
        bribeFactory = _bribes;
        v2Factory = _v2Factory;
        v3Factory = _v3Factory;
        governor = msg.sender;
        emergencyCouncil = msg.sender;
    }

    modifier onlyNewEpoch(uint _tokenId) {
        // ensure new epoch since last vote 
        require((block.timestamp / DURATION) * DURATION > lastVoted[_tokenId], "TOKEN_ALREADY_VOTED_THIS_EPOCH");
        _;
    }

    function initialize(address[] memory _tokens) external {
        for (uint i = 0; i < _tokens.length; i++) {
            _whitelist(_tokens[i]);
        }
    }

    function setGovernor(address _governor) public {
        require(msg.sender == governor);
        governor = _governor;
    }

    function setEmergencyCouncil(address _council) public {
        require(msg.sender == emergencyCouncil);
        emergencyCouncil = _council;
    }

    function reset(uint _tokenId) external onlyNewEpoch(_tokenId) {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
        lastVoted[_tokenId] = block.timestamp;
        _reset(_tokenId);
        IVotingEscrow(_ve).abstain(_tokenId);
    }

    function _reset(uint _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint i = 0; i < _poolVoteCnt; i ++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                weights[_pool] -= _votes;
                votes[_tokenId][_pool] -= _votes;
                if (_votes > 0) {
                    IBribe(external_bribes[_pool])._withdraw(uint256(_votes), _tokenId);
                    _totalWeight += _votes;
                } else {
                    _totalWeight -= _votes;
                }
                emit Abstained(_tokenId, _votes);
            }
        }
        totalWeight -= uint256(_totalWeight);
        usedWeights[_tokenId] = 0;
        delete poolVote[_tokenId];
    }

    function poke(uint _tokenId) external {
        address[] memory _poolVote = poolVote[_tokenId];
        uint _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint i = 0; i < _poolCnt; i ++) {
            _weights[i] = votes[_tokenId][_poolVote[i]];
        }

        _vote(_tokenId, _poolVote, _weights);
    }

    function _vote(uint _tokenId, address[] memory _poolVote, uint256[] memory _weights) internal {
        _reset(_tokenId);
        uint _poolCnt = _poolVote.length;
        uint256 _weight = IVotingEscrow(_ve).balanceOfNFT(_tokenId);
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];

            if (isVoteable[_pool]) {
                uint256 _poolWeight = _weights[i] * _weight / _totalVoteWeight;
                require(votes[_tokenId][_pool] == 0);
                require(_poolWeight != 0);

                poolVote[_tokenId].push(_pool);

                weights[_pool] += _poolWeight;
                votes[_tokenId][_pool] += _poolWeight;
                IBribe(external_bribes[_pool])._deposit(uint256(_poolWeight), _tokenId);
                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;
                emit Voted(msg.sender, _tokenId, _poolWeight);
            }
        }
        if (_usedWeight > 0) IVotingEscrow(_ve).voting(_tokenId);
        totalWeight += uint256(_totalWeight);
        usedWeights[_tokenId] = uint256(_usedWeight);
    }

    function vote(uint tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external onlyNewEpoch(tokenId) {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, tokenId));
        require(_poolVote.length == _weights.length);
        lastVoted[tokenId] = block.timestamp;
        _vote(tokenId, _poolVote, _weights);
    }

    function whitelist(address _token) public {
        require(msg.sender == governor);
        _whitelist(_token);
    }

    function _whitelist(address _token) internal {
        require(!isWhitelisted[_token]);
        isWhitelisted[_token] = true;
        emit Whitelisted(msg.sender, _token);
    }


    function addVoteablePool(address _externalPool, address _tokenA, address _tokenB, uint24 _fee) external {
        
        address pool;
        address[] memory allowedRewards = new address[](3);
        PoolType poolType;
        if(_externalPool != address(0)){
            require(msg.sender == governor, "forbidden");
            pool = _externalPool;
            poolType = PoolType.EXTERNAL_POOL;
        }else{
            require(_tokenA != address(0) && _tokenB != address(0), "zero address");
            if(_fee > 0){  //V3
                pool = IV3Factory(v3Factory).getPool(_tokenA, _tokenB, _fee);
                poolType = PoolType.V3_POOL;
            }else{  //V2
                pool = IV2Factory(v2Factory).getPair(_tokenA, _tokenB);
                poolType = PoolType.V2_POOL;
            }
            require(pool != address(0), "pool not found");
            allowedRewards[0] = _tokenA;
            allowedRewards[1] = _tokenB;
        }
        
        require(!isVoteable[pool], "already exists");

        if(external_bribes[pool] == address(0)){  //First time
            address _external_bribe = IBribeFactory(bribeFactory).createExternalBribe(allowedRewards);
            external_bribes[pool] = _external_bribe;
            pools.push(pool);
            poolTypes[pool] = poolType;
        }

        isVoteable[pool] = true;
        emit VoteablePoolAdded(msg.sender, external_bribes[pool], pool);
    }

    function removeVoteablePool(address _pool) external {
        require(msg.sender == emergencyCouncil, "not emergency council");
        require(isVoteable[_pool], "already removed");
        isVoteable[_pool] = false;
        emit VoteablePoolRemoved(_pool);
    }

    function length() external view returns (uint) {
        return pools.length;
    }

    function claimBribes(address[] memory _bribes, address[][] memory _tokens, uint _tokenId) external {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, _tokenId));
        for (uint i = 0; i < _bribes.length; i++) {
            IBribe(_bribes[i]).getRewardForOwner(_tokenId, _tokens[i]);
        }
    }

}
