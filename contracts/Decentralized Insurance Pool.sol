// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


/**
 * @title Decentralized Insurance Pool
 * @dev A peer-to-peer insurance system where users contribute to risk pools and can file claims
 */
contract Project {

    struct Policy {
        address policyholder;
        uint256 premiumPaid;
        uint256 coverageAmount;
        uint256 startTime;
        uint256 duration;
        bool isActive;
        bool hasClaimed;
    }

    struct Claim {
        uint256 policyId;
        address claimant;
        uint256 claimAmount;
        string description;
        uint256 timestamp;
        uint256 votesFor;
        uint256 votesAgainst;
        bool resolved;
        bool approved;
        mapping(address => bool) hasVoted;
    }

    // State variables
    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim) public claims;
    mapping(address => uint256[]) public userPolicies;

    uint256 public nextPolicyId = 1;
    uint256 public nextClaimId = 1;
    uint256 public totalPoolFunds;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant MIN_VOTES_REQUIRED = 3;

    // Events
    event PolicyCreated(uint256 indexed policyId, address indexed policyholder, uint256 coverageAmount);
    event ClaimSubmitted(uint256 indexed claimId, uint256 indexed policyId, address indexed claimant, uint256 amount);
    event ClaimVoted(uint256 indexed claimId, address indexed voter, bool support);
    event ClaimResolved(uint256 indexed claimId, bool approved, uint256 payoutAmount);
    event FundsDeposited(address indexed contributor, uint256 amount);
    event PolicyCancelled(uint256 indexed policyId, address indexed policyholder, uint256 refundAmount); // New Event

    // Modifiers
    modifier onlyActivePolicyHolder(uint256 _policyId) {
        require(policies[_policyId].isActive, "Policy is not active");
        require(policies[_policyId].policyholder == msg.sender, "Not the policyholder");
        require(block.timestamp < policies[_policyId].startTime + policies[_policyId].duration, "Policy expired");
        _;
    }

    modifier claimExists(uint256 _claimId) {
        require(_claimId < nextClaimId, "Claim does not exist");
        _;
    }

    function createPolicy(uint256 _coverageAmount, uint256 _duration) external payable {
        require(msg.value > 0, "Premium must be greater than 0");
        require(_coverageAmount > 0, "Coverage amount must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(msg.value >= _coverageAmount / 20, "Premium too low (minimum 5% of coverage)");

        uint256 policyId = nextPolicyId++;

        policies[policyId] = Policy({
            policyholder: msg.sender,
            premiumPaid: msg.value,
            coverageAmount: _coverageAmount,
            startTime: block.timestamp,
            duration: _duration,
            isActive: true,
            hasClaimed: false
        });

        userPolicies[msg.sender].push(policyId);
        totalPoolFunds += msg.value;

        emit PolicyCreated(policyId, msg.sender, _coverageAmount);
        emit FundsDeposited(msg.sender, msg.value);
    }

    function submitClaim(
        uint256 _policyId, 
        uint256 _claimAmount, 
        string memory _description
    ) external onlyActivePolicyHolder(_policyId) {
        require(!policies[_policyId].hasClaimed, "Policy has already been claimed");
        require(_claimAmount <= policies[_policyId].coverageAmount, "Claim exceeds coverage amount");
        require(_claimAmount <= totalPoolFunds, "Insufficient pool funds");
        require(bytes(_description).length > 0, "Description required");

        uint256 claimId = nextClaimId++;

        Claim storage newClaim = claims[claimId];
        newClaim.policyId = _policyId;
        newClaim.claimant = msg.sender;
        newClaim.claimAmount = _claimAmount;
        newClaim.description = _description;
        newClaim.timestamp = block.timestamp;
        newClaim.resolved = false;
        newClaim.approved = false;

        emit ClaimSubmitted(claimId, _policyId, msg.sender, _claimAmount);
    }

    function voteOnClaim(uint256 _claimId, bool _support) external claimExists(_claimId) {
        Claim storage claim = claims[_claimId];

        require(!claim.resolved, "Claim already resolved");
        require(!claim.hasVoted[msg.sender], "Already voted on this claim");
        require(block.timestamp <= claim.timestamp + VOTING_PERIOD, "Voting period has ended");
        require(userPolicies[msg.sender].length > 0, "Must be a policyholder to vote");

        claim.hasVoted[msg.sender] = true;

        if (_support) {
            claim.votesFor++;
        } else {
            claim.votesAgainst++;
        }

        emit ClaimVoted(_claimId, msg.sender, _support);

        if (claim.votesFor + claim.votesAgainst >= MIN_VOTES_REQUIRED) {
            _resolveClaim(_claimId);
        }
    }

    function _resolveClaim(uint256 _claimId) internal {
        Claim storage claim = claims[_claimId];
        require(!claim.resolved, "Claim already resolved");

        claim.resolved = true;

        if (claim.votesFor > claim.votesAgainst) {
            claim.approved = true;
            policies[claim.policyId].hasClaimed = true;

            uint256 payoutAmount = claim.claimAmount;
            if (payoutAmount > totalPoolFunds) {
                payoutAmount = totalPoolFunds;
            }

            totalPoolFunds -= payoutAmount;
            payable(claim.claimant).transfer(payoutAmount);

            emit ClaimResolved(_claimId, true, payoutAmount);
        } else {
            emit ClaimResolved(_claimId, false, 0);
        }
    }

    function resolveClaim(uint256 _claimId) external claimExists(_claimId) {
        Claim storage claim = claims[_claimId];
        require(!claim.resolved, "Claim already resolved");
        require(
            block.timestamp > claim.timestamp + VOTING_PERIOD || 
            claim.votesFor + claim.votesAgainst >= MIN_VOTES_REQUIRED, 
            "Voting still active or insufficient votes"
        );

        _resolveClaim(_claimId);
    }

    function contributeToPool() external payable {
        require(msg.value > 0, "Contribution must be greater than 0");
        totalPoolFunds += msg.value;
        emit FundsDeposited(msg.sender, msg.value);
    }

    function getPolicyDetails(uint256 _policyId) external view returns (
        address policyholder,
        uint256 premiumPaid,
        uint256 coverageAmount,
        uint256 startTime,
        uint256 duration,
        bool isActive,
        bool hasClaimed
    ) {
        Policy storage policy = policies[_policyId];
        return (
            policy.policyholder,
            policy.premiumPaid,
            policy.coverageAmount,
            policy.startTime,
            policy.duration,
            policy.isActive,
            policy.hasClaimed
        );
    }

    function getClaimDetails(uint256 _claimId) external view returns (
        uint256 policyId,
        address claimant,
        uint256 claimAmount,
        string memory description,
        uint256 timestamp,
        uint256 votesFor,
        uint256 votesAgainst,
        bool resolved,
        bool approved
    ) {
        Claim storage claim = claims[_claimId];
        return (
            claim.policyId,
            claim.claimant,
            claim.claimAmount,
            claim.description,
            claim.timestamp,
            claim.votesFor,
            claim.votesAgainst,
            claim.resolved,
            claim.approved
        );
    }

    function getUserPolicies(address _user) external view returns (uint256[] memory) {
        return userPolicies[_user];
    }

    function getPoolStats() external view returns (
        uint256 contractBalance,
        uint256 totalFunds,
        uint256 totalPolicies,
        uint256 totalClaims
    ) {
        return (
            address(this).balance,
            totalPoolFunds,
            nextPolicyId - 1,
            nextClaimId - 1
        );
    }

    /**
     * @dev Cancel an active policy before it expires and receive a partial refund
     * @param _policyId The ID of the policy to cancel
     */
    function cancelPolicy(uint256 _policyId) external onlyActivePolicyHolder(_policyId) {
        Policy storage policy = policies[_policyId];
        require(!policy.hasClaimed, "Cannot cancel after a claim");

        uint256 elapsedTime = block.timestamp - policy.startTime;
        uint256 remainingTime = policy.duration > elapsedTime ? policy.duration - elapsedTime : 0;

        uint256 refundAmount = (policy.premiumPaid * remainingTime) / policy.duration;

        policy.isActive = false;

        if (refundAmount > 0 && refundAmount <= totalPoolFunds) {
            totalPoolFunds -= refundAmount;
            payable(msg.sender).transfer(refundAmount);
        }

        emit PolicyCancelled(_policyId, msg.sender, refundAmount);
    }
}
 
