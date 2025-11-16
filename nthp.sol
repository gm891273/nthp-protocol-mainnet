// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 NTHP Protocol v1.0.3b (stackfix)
 Tax-free + zero privacy impact on the main token + three interface modules (ParamStore / TreasuryExecutor / KeeperRouter)
 - Main token: pure ERC20 + ERC20Permit + ERC20Votes (no tax / no blacklist / no pause / no hooks / no extra events)
 - Modules: StakingVault / VestingVault / LightMixer / ParamStore / TreasuryExecutor / KeeperRouter
 - Decentralization / power hand-off: finalize() → transfer all owners to Timelock; Timelock has no admin; Governor is proposer/canceller; executor = any
 - “Stack too deep” fix: split the original long constructor into 3 initialization functions
 - TimelockController constructor uses empty address arrays:
   new address, new address, address(this)
*/

import "@openzeppelin/contracts@4.9.3/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.9.3/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts@4.9.3/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.3/governance/TimelockController.sol";
import "@openzeppelin/contracts@4.9.3/governance/Governor.sol";
import "@openzeppelin/contracts@4.9.3/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts@4.9.3/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts@4.9.3/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts@4.9.3/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts@4.9.3/governance/extensions/GovernorTimelockControl.sol";

/*──────────────────────── Main Token (no tax) ─────────────────────*/
contract NTHP_Final is ERC20, ERC20Permit, ERC20Votes, Ownable {
    string  private constant _NAME   = unicode"Nthpower";
    string  private constant _SYMBOL = "NTHP";
    uint256 public constant CAP     = 66_660_000 * 1e18;
    function decimals() public pure override returns (uint8) { return 18; }

    constructor(address owner_, address holder_) ERC20(_NAME, _SYMBOL) ERC20Permit(_NAME) {
        require(owner_ != address(0) && holder_ != address(0), "addr=0");
        _transferOwnership(owner_);
        _mint(holder_, CAP);
    }

    function _transfer(address from, address to, uint256 amount) internal override(ERC20) {
        super._transfer(from, to, amount);
    }
    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal override(ERC20, ERC20Votes) { super._afterTokenTransfer(from, to, amount); }
    function _mint(address to, uint256 amount)
        internal override(ERC20, ERC20Votes) { super._mint(to, amount); }
    function _burn(address from, uint256 amount)
        internal override(ERC20, ERC20Votes) { super._burn(from, amount); }
}

/*──────────────────────── Staking Vault ─────────────────────*/
contract StakingVault is ReentrancyGuard, Ownable {
    IERC20  public immutable token;
    uint256 public rewardRate;
    uint256 public lockPeriod;
    uint256 public lastUpdate;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;

    mapping(address => uint256) public userStake;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public unlockTime;

    event Params(uint256 rewardRate, uint256 lockPeriod);
    event Funded(uint256 amount);
    event Staked(address indexed user, uint256 received);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(IERC20 _token, uint256 _rewardRatePerSec, uint256 _lockPeriod) {
        require(address(_token) != address(0), "token=0");
        token = _token;
        rewardRate = _rewardRatePerSec;
        lockPeriod = _lockPeriod;
        lastUpdate = block.timestamp;
    }

    function setParams(uint256 _rewardRatePerSec, uint256 _lockPeriod) external onlyOwner {
        _updateReward(address(0));
        rewardRate = _rewardRatePerSec;
        lockPeriod = _lockPeriod;
        emit Params(rewardRate, lockPeriod);
    }

    function addRewards(uint256 amount) external nonReentrant {
        require(amount > 0, "0");
        uint256 b0 = IERC20(token).balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), amount), "fund fail");
        uint256 received = IERC20(token).balanceOf(address(this)) - b0;
        require(received > 0, "no receive");
        emit Funded(received);
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "0");
        _updateReward(msg.sender);
        uint256 b0 = IERC20(token).balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), amount), "tf fail");
        uint256 received = IERC20(token).balanceOf(address(this)) - b0;
        require(received > 0, "no recv");
        userStake[msg.sender] += received;
        totalStaked += received;
        if (unlockTime[msg.sender] < block.timestamp) {
            unlockTime[msg.sender] = block.timestamp + lockPeriod;
        }
        emit Staked(msg.sender, received);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0 && userStake[msg.sender] >= amount, "bad");
        if (lockPeriod > 0) require(block.timestamp >= unlockTime[msg.sender], "locked");
        _updateReward(msg.sender);
        userStake[msg.sender] -= amount;
        totalStaked -= amount;
        require(token.transfer(msg.sender, amount), "t fail");
        emit Unstaked(msg.sender, amount);
    }

    function getReward() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "no reward");
        rewards[msg.sender] = 0;
        require(token.transfer(msg.sender, reward), "pay fail");
        emit RewardPaid(msg.sender, reward);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        uint256 dt = block.timestamp - lastUpdate;
        return rewardPerTokenStored + (dt * rewardRate * 1e18) / totalStaked;
    }
    function earned(address account) public view returns (uint256) {
        return (userStake[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }
    function _updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdate = block.timestamp;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }
}

/*──────────────────────── Vesting Vault ─────────────────────*/
contract VestingVault is ReentrancyGuard, Ownable {
    IERC20  public immutable token;
    address public immutable beneficiary;
    uint256 public immutable startTime;
    uint256 public immutable totalAmount;

    uint256 public constant PERIOD   = 180 days;
    uint256 public constant DURATION = 5 * 365 days;
    uint256 public constant PERIODS  = DURATION / PERIOD; // 10 periods
    uint256 public claimed;

    event Claimed(uint256 amount, uint256 timestamp);

    constructor(IERC20 _token, address _beneficiary, uint256 _totalAmount) {
        require(address(_token) != address(0) && _beneficiary != address(0), "zero");
        require(_totalAmount > 0, "amt");
        token = _token;
        beneficiary = _beneficiary;
        totalAmount = _totalAmount;
        startTime = block.timestamp;
    }

    function currentPeriod() public view returns (uint256) {
        if (block.timestamp <= startTime) return 0;
        uint256 p = (block.timestamp - startTime) / PERIOD;
        if (p >= PERIODS) return PERIODS;
        return p;
    }
    function amountPerPeriod() public view returns (uint256 base, uint256 remainder) {
        base = totalAmount / PERIODS;
        remainder = totalAmount - base * PERIODS;
    }
    function vested() public view returns (uint256) {
        uint256 p = currentPeriod();
        if (p == 0) return 0;
        if (p >= PERIODS) return totalAmount;
        (uint256 base, uint256 rem) = amountPerPeriod();
        uint256 unlocked = base * p;
        if (p == PERIODS - 1) unlocked += rem;
        return unlocked;
    }
    function releasable() public view returns (uint256) {
        uint256 v = vested();
        return v > claimed ? v - claimed : 0;
    }
    function claim() external nonReentrant {
        require(msg.sender == beneficiary, "not bene");
        uint256 amt = releasable();
        require(amt > 0, "0");
        claimed += amt;
        require(token.transfer(beneficiary, amt), "transfer fail");
        emit Claimed(amt, block.timestamp);
    }
}

/*──────────────────────── Light Privacy Mixer ───────────*/
contract NTHP_LightMixer is ReentrancyGuard, Ownable {
    IERC20  public immutable token;
    address public treasury;
    uint32  public feePpb;                        // ≤0.01% (100_000)
    uint32  public constant DEN = 1_000_000_000;
    uint256 public minBatch = 3;
    uint256 public maxDelay = 600;
    uint256 public maxBatchSize = 50;
    uint256 public lastBatchTime;

    struct Entry { address from; address to; uint256 amount; }
    Entry[] private q;

    event Params(address treasury, uint32 feePpb, uint256 minBatch, uint256 maxDelay, uint256 maxBatchSize);
    event Deposited(address indexed from, address indexed to, uint256 amount);
    event Processed(uint256 count, uint256 feeTotal, uint256 when);

    constructor(IERC20 _token, address _treasury, uint32 _feePpb, uint256 _minBatch, uint256 _maxDelay){
        require(address(_token)!=address(0),"token=0");
        require(_feePpb<=100_000,"fee>0.01%");
        token=_token; treasury=_treasury; feePpb=_feePpb;
        if (_minBatch>0) minBatch=_minBatch; if (_maxDelay>0) maxDelay=_maxDelay;
        lastBatchTime=block.timestamp;
    }
    function setParams(address _treasury,uint32 _feePpb,uint256 _minBatch,uint256 _maxDelay,uint256 _maxBatchSize) external onlyOwner {
        require(_feePpb<=100_000,"fee>0.01%");
        require(_minBatch>0 && _maxDelay>0 && _maxBatchSize>0,"bad");
        treasury=_treasury; feePpb=_feePpb; minBatch=_minBatch; maxDelay=_maxDelay; maxBatchSize=_maxBatchSize;
        emit Params(_treasury,_feePpb,_minBatch,_maxDelay,_maxBatchSize);
    }
    function deposit(address to,uint256 amount) external nonReentrant {
        require(to!=address(0) && amount>0,"bad");
        require(token.transferFrom(msg.sender,address(this),amount),"tf fail");
        q.push(Entry({from:msg.sender,to:to,amount:amount}));
        emit Deposited(msg.sender,to,amount);
    }
    function ready() public view returns(bool){
        if (q.length>=minBatch) return true;
        if (q.length>0 && block.timestamp-lastBatchTime>=maxDelay) return true;
        return false;
    }
    function processBatch() external nonReentrant {
        require(ready(),"not ready");
        uint256 n=q.length; require(n>0,"empty");
        uint256 m = n>maxBatchSize ? maxBatchSize : n;

        Entry[] memory a=new Entry[](m);
        for(uint256 i=0;i<m;i++) a[i]=q[n - m + i];

        bytes32 seed=keccak256(abi.encodePacked(blockhash(block.number-1),m,gasleft(),address(this)));
        if (m>1) {
            for(uint256 i=m-1;i>0;i--){
                uint256 j=uint256(keccak256(abi.encodePacked(seed,i)))%(i+1);
                Entry memory tmp=a[i];a[i]=a[j];a[j]=tmp;
            }
        }

        uint256 feeTotal;
        for(uint256 i=0;i<m;i++){
            uint256 fee=(feePpb==0 || treasury==address(0)) ? 0 : (a[i].amount*feePpb)/DEN;
            uint256 net=a[i].amount-fee;
            if (fee>0) {require(token.transfer(treasury,fee),"fee fail");feeTotal+=fee;}
            require(token.transfer(a[i].to,net),"net fail");
        }

        for(uint256 i=0;i<m;i++) delete q[n-m+i];
        lastBatchTime=block.timestamp;

        emit Processed(m,feeTotal,block.timestamp);
    }
}

/*──────────────────────── Governance Module ─────────────────────*/
contract NTHPGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumPercent_
    )
        Governor("NTHP Governor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(quorumPercent_)
        GovernorTimelockControl(_timelock)
    {}

    function votingDelay()
        public view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    { return super.votingDelay(); }

    function votingPeriod()
        public view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    { return super.votingPeriod(); }

    function quorum(uint256 blockNumber)
        public view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    { return super.quorum(blockNumber); }

    function proposalThreshold()
        public view
        override(Governor, GovernorSettings)
        returns (uint256)
    { return super.proposalThreshold(); }

    function state(uint256 proposalId)
        public view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    { return super.state(proposalId); }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
    { super._execute(proposalId, targets, values, calldatas, descriptionHash); }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint256)
    { return super._cancel(targets, values, calldatas, descriptionHash); }

    function _executor()
        internal view
        override(Governor, GovernorTimelockControl)
        returns (address)
    { return super._executor(); }

    function supportsInterface(bytes4 interfaceId)
        public view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    { return super.supportsInterface(interfaceId); }
}

/*──────────────────────── Parameter Store ─────────────*/
contract NTHP_ParamStore is Ownable {
    mapping(bytes32 => address) public addr;
    mapping(bytes32 => uint256) public num;
    event AddrSet(bytes32 indexed key, address value);
    event NumSet(bytes32 indexed key, uint256 value);
    function setAddr(bytes32 k, address v) external onlyOwner { addr[k]=v; emit AddrSet(k,v); }
    function setNum(bytes32 k, uint256 v) external onlyOwner { num[k]=v; emit NumSet(k,v); }
}

/*──────────────────────── Treasury Executor ─────────────*/
contract NTHP_TreasuryExecutor is Ownable {
    mapping(address => bool) public allowedTarget;
    event TargetAllowed(address indexed target, bool allowed);
    event Executed(address indexed target, uint256 value, bytes data);
    receive() external payable {}

    function setAllowedTarget(address target, bool allowed) external onlyOwner {
        allowedTarget[target] = allowed;
        emit TargetAllowed(target, allowed);
    }

    function approveToken(address erc20, address spender, uint256 amount) external onlyOwner {
        require(erc20 != address(0) && spender != address(0), "zero");
        require(IERC20(erc20).approve(spender, amount), "approve fail");
    }

    function exec(address target, uint256 value, bytes calldata data)
        external onlyOwner returns (bytes memory)
    {
        require(allowedTarget[target], "target !allowed");
        (bool ok, bytes memory res) = target.call{value:value}(data);
        require(ok, "call fail");
        emit Executed(target, value, data);
        return res;
    }
}

/*──────────────────────── Automation Keeper Router ─────────*/
contract NTHP_KeeperRouter is Ownable {
    address public keeper;
    mapping(address => bool) public allowedTarget;
    mapping(bytes4 => bool) public allowedSelector;

    event KeeperSet(address indexed keeper);
    event TargetAllowed(address indexed target, bool allowed);
    event SelectorAllowed(bytes4 indexed sel, bool allowed);
    event Triggered(address indexed target, bytes data);

    function setKeeper(address k) external onlyOwner {
        keeper = k; emit KeeperSet(k);
    }
    function setTargetAllowed(address target, bool allowed) external onlyOwner {
        allowedTarget[target] = allowed; emit TargetAllowed(target, allowed);
    }
    function setSelectorAllowed(bytes4 sel, bool allowed) external onlyOwner {
        allowedSelector[sel] = allowed; emit SelectorAllowed(sel, allowed);
    }

    function trigger(address target, bytes calldata data) external {
        require(msg.sender == keeper, "not keeper");
        require(allowedTarget[target], "target !allowed");
        require(data.length >= 4, "data<4");
        bytes4 sel; assembly { sel := shr(224, calldataload(data.offset)) }
        require(allowedSelector[sel], "selector !allowed");
        (bool ok, ) = target.call(data); require(ok, "call fail");
        emit Triggered(target, data);
    }
}

/*──────────────────────── Combined Deployer (step-by-step init) ─────────────────────*/
contract CombinedDeployer is Ownable, ReentrancyGuard {
    NTHP_Final public token;
    StakingVault public staking;
    VestingVault public vesting;
    NTHP_LightMixer public mixer;

    TimelockController public timelock;
    NTHPGovernor public governor;

    NTHP_ParamStore public paramStore;
    NTHP_TreasuryExecutor public treasuryExecutor;
    NTHP_KeeperRouter public keeperRouter;

    bool public finalized;

    // Flags for init steps
    bool public govReady;
    bool public stakingReady;
    bool public mixerReady;

    address public immutable initialHolder;
    address public immutable initialMixerTreasury;

    constructor(
        address owner_,
        address holder_,
        address initialMixerTreasury_
    ) {
        require(owner_ != address(0) && holder_ != address(0) && initialMixerTreasury_ != address(0), "bad addr");
        _transferOwnership(owner_);
        initialHolder = holder_;
        initialMixerTreasury = initialMixerTreasury_;

        // First deploy main token (owner = this deployer), mint full supply to holder_
        token = new NTHP_Final(address(this), holder_);

        // Deploy three interface modules first (no constructor params, avoids deep stack)
        paramStore = new NTHP_ParamStore();
        treasuryExecutor = new NTHP_TreasuryExecutor();
        keeperRouter = new NTHP_KeeperRouter();
    }

    // Step 1: Governance (deploy Timelock and Governor first)
    function initGovernance(
        uint256 timelockDelaySec_,
        uint256 votingDelayBlocks_,
        uint256 votingPeriodBlocks_,
        uint256 proposalThresholdVotes_,
        uint256 quorumPercent_
    ) external onlyOwner nonReentrant {
        require(!govReady, "gov inited");

        timelock = new TimelockController(
            timelockDelaySec_,
            new address[](0),
            new address[](0),
            address(this)
        );
        governor = new NTHPGovernor(
            IVotes(address(token)),
            timelock,
            votingDelayBlocks_,
            votingPeriodBlocks_,
            proposalThresholdVotes_,
            quorumPercent_
        );
        govReady = true;
    }

    // Step 2: Staking & Vesting (vesting is optional)
    function initStakingAndVesting(
        address vestingBeneficiary_,   // = address(0) means vesting is disabled
        uint256 vestingAmount_,        // = 0 means vesting is disabled
        uint256 rewardRatePerSec_,
        uint256 stakeLockPeriodSec_
    ) external onlyOwner nonReentrant {
        require(govReady, "init gov first");
        require(!stakingReady, "staking inited");

        staking = new StakingVault(IERC20(address(token)), rewardRatePerSec_, stakeLockPeriodSec_);
        if (vestingAmount_ > 0) {
            require(vestingBeneficiary_ != address(0), "bene=0");
            vesting = new VestingVault(IERC20(address(token)), vestingBeneficiary_, vestingAmount_);
        }
        stakingReady = true;
    }

    // Step 3: Mixer (after governance is ready, set treasury = Timelock)
    function initMixer(
        uint32 mixerFeePpb_,          // ≤ 100_000 (0.01%)
        uint256 mixerMinBatch_,
        uint256 mixerMaxDelaySec_,
        uint256 mixerMaxBatchSize_
    ) external onlyOwner nonReentrant {
        require(govReady, "init gov first");
        require(!mixerReady, "mixer inited");

        // First create using initialMixerTreasury, then immediately switch treasury to Timelock
        mixer = new NTHP_LightMixer(
            IERC20(address(token)),
            initialMixerTreasury,
            mixerFeePpb_,
            mixerMinBatch_,
            mixerMaxDelaySec_
        );
        mixer.setParams(address(timelock), mixerFeePpb_, mixerMinBatch_, mixerMaxDelaySec_, mixerMaxBatchSize_);
        mixerReady = true;
    }

    // Final step: hand over control / decentralize
    function finalize() external onlyOwner nonReentrant {
        require(!finalized, "finalized");
        require(govReady && stakingReady && mixerReady, "init incomplete");

        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();

        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));
        timelock.grantRole(EXECUTOR_ROLE, address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        token.transferOwnership(address(timelock));
        staking.transferOwnership(address(timelock));
        if (address(vesting) != address(0)) vesting.transferOwnership(address(timelock));
        mixer.transferOwnership(address(timelock));
        paramStore.transferOwnership(address(timelock));
        treasuryExecutor.transferOwnership(address(timelock));
        keeperRouter.transferOwnership(address(timelock));

        finalized = true;
    }

    function getAddresses()
        external view
        returns (
            address token_,
            address staking_,
            address vesting_,
            address mixer_,
            address timelock_,
            address governor_,
            address paramStore_,
            address treasuryExecutor_,
            address keeperRouter_
        )
    {
        return (
            address(token),
            address(staking),
            address(vesting),
            address(mixer),
            address(timelock),
            address(governor),
            address(paramStore),
            address(treasuryExecutor),
            address(keeperRouter)
        );
    }
}
