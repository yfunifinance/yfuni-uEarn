// SPDX-License-Identifier: none

pragma solidity >=0.5.0 <0.9.0;

import "./uEarn.sol";

contract YFUNIuEarn is uEarn{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    mapping (uint => eventStaking) private stakingEvent;
    mapping (uint => uint256) private totalClaimed;
    mapping (uint => address) private rewardAddress;
    mapping (address => mapping (uint => bool)) private eventClaim;
    
    uint private activeEventId;
    uint[] private events;
    
    struct eventStaking{
        bool stakeMustActive;
        uint poolIdGotEvent;
        uint256 dateRange1;
        uint256 dateRange2;
        uint256 stakeTimeElapsed;
        uint256 snapshotReward;
        uint256 totalReward;
    }
    
    struct pairLooker{
        uint8 pair2decimal;
        address pair2address;
        string pair2symbol;
    }
    
    struct userLooker{
        bool activestake;
        uint periodChoosed;
        uint pairChoosed;
        uint256 amountstaked;
        uint256 startstake;
        uint256 reaminingReward;
    }
    
    constructor (address data) {
        _setAdmin(data);
    }
    
    function createNewEvent(uint specificPoolId, uint256 startDateFilter, uint256 endDateFilter, uint256 specificElapsedTime, uint256 totalReward) public payable virtual onlyOwner{
        (
            uint8 pair2decimal,
            address pair2address,
            string memory pair2symbol  
        ) = _getPairInfoForEvent(specificPoolId);
        pairLooker memory sp = pairLooker(pair2decimal, pair2address, pair2symbol);
        
        require(specificPoolId > 0, "Pool poolIdGotEvent must greater than 0");
        require(startDateFilter > 0, "Start date must greater than 0");
        require(endDateFilter > 0, "End date must greater than 0");
        require(getPoolBalance(sp.pair2address) > getRewardAllocation(sp.pair2address), "Pool reward must greater than reward allocation");
        
        address msgSender = _msgSender();
        uint getEventLength = events.length;
        uint newEventId = getEventLength + 1;
        
        eventStaking storage ev = stakingEvent[newEventId];
        
        ev.stakeMustActive = true;
        ev.poolIdGotEvent = specificPoolId;
        ev.dateRange1 = startDateFilter;
        ev.dateRange2 = endDateFilter;
        ev.stakeTimeElapsed = specificElapsedTime;
        ev.snapshotReward = getRewardAllocation(sp.pair2address);
        ev.totalReward = totalReward;
        
        if(sp.pair2address == address(0)){
            require(msg.value >= totalReward, "Value reward must same with argument");
        }else{
            uint256 getallowance = IERC20(sp.pair2address).allowance(msgSender, address(this));
            require(getallowance >= totalReward, "Insufficient token approval balance, you must increase your allowance" );
            IERC20(sp.pair2address).safeTransferFrom(msgSender, address(this), totalReward);
        }
        
        rewardAddress[newEventId] = sp.pair2address;
        activeEventId = newEventId;
        events.push(newEventId);
    }
    
    function closeActiveEvent() public virtual onlyOwner{
        eventStaking storage ev = stakingEvent[activeEventId];
        uint256 ream = ev.totalReward.sub(totalClaimed[activeEventId]);
        totalClaimed[activeEventId] = totalClaimed[activeEventId].add(ream);
        activeEventId = 0;
    }
    
    function userEventClaim() public virtual{
        address msgSender = _msgSender();
        
        require(checkEligibleUser(msgSender, activeEventId) == true, "Unfortunately, you not eligible");
        
        uint256 getUserAllocationReward = userRewardCalculator(msgSender, activeEventId);
        eventClaim[msgSender][activeEventId] = true;
        totalClaimed[activeEventId] = totalClaimed[activeEventId].add(getUserAllocationReward);
        
        if(viewActiveRewardAddress() == address(0)){
            payable(msgSender).transfer(getUserAllocationReward);
        }else{
            IERC20(viewActiveRewardAddress()).safeTransfer(msgSender, getUserAllocationReward);
        }
    }
    
    function viewDetailEvent(uint eventId) public view returns(bool, uint, uint256, uint256, uint256, uint256, uint256){
        eventStaking storage ev = stakingEvent[eventId];
        
        return(
            ev.stakeMustActive,
            ev.poolIdGotEvent,
            ev.dateRange1,
            ev.dateRange2,
            ev.stakeTimeElapsed,
            ev.snapshotReward,
            ev.totalReward
        );
    }
    
    function viewReaminingReward(uint eventId) public view returns(uint256){
        eventStaking storage ev = stakingEvent[eventId];
        uint256 ream = ev.totalReward.sub(totalClaimed[eventId]);
        return ream;
    }
    
    function viewActiveEvent() public view returns(uint){
        return activeEventId;
    }
    
    function viewActiveRewardAddress() public view returns(address){
        return rewardAddress[activeEventId];
    }
    
    function checkEligibleUser(address participant, uint eventId) public view returns(bool){
        bool eligibledUser = false;
        
        if(eventClaim[participant][eventId] == false){
            if(_checkEligibleEvent(participant, eventId) == true){
                eligibledUser = true;
            }
        }
        
        return eligibledUser;
    }
    
    function userRewardCalculator(address participant, uint eventId) public view returns(uint256){
        (
            bool activestake,
            uint periodChoosed,
            uint pairChoosed,
            uint256 amountstaked,
            uint256 startstake,
            uint256 reaminingReward
        ) = _getUserInfo(participant);
        
        eventStaking memory ev = stakingEvent[eventId];
        userLooker memory lookup = userLooker(activestake, periodChoosed, pairChoosed, amountstaked, startstake, reaminingReward);
        
        uint256 getUserReward;
        
        if(lookup.reaminingReward > 0){
            uint256 getTotalReward = ev.totalReward;
            uint256 getUserReaminingReward = lookup.reaminingReward;
            uint256 getTotalAllocation = ev.snapshotReward;
            
            getUserReward = getTotalReward.mul(getUserReaminingReward);
            getUserReward = getUserReward.div(getTotalAllocation);
        }
        
        return getUserReward;
    }
    
    function _checkEligibleEvent(address participant, uint eventId) internal view returns(bool){
        (
            bool activestake,
            uint periodChoosed,
            uint pairChoosed,
            uint256 amountstaked,
            uint256 startstake,
            uint256 reaminingReward
        ) = _getUserInfo(participant);
        
        eventStaking memory ev = stakingEvent[eventId];
        userLooker memory lookup = userLooker(activestake, periodChoosed, pairChoosed, amountstaked, startstake, reaminingReward);
        
        bool statusActiveCheck = false;
        bool periodChoosedCheck = false;
        bool startDateUnderRangeCheck = false;
        bool stakeElapsedTimeCheck = false;
        bool isEligible = false;
        
        if(ev.stakeMustActive == true){
            if(lookup.activestake == ev.stakeMustActive){
                statusActiveCheck = true;
            }
        }else{
            statusActiveCheck = true;
        }
        
        if(ev.poolIdGotEvent == 0){
            periodChoosedCheck = true;
        }else{
            if(lookup.pairChoosed == ev.poolIdGotEvent){
                periodChoosedCheck = true;
            }
        }
        
        if(lookup.startstake >= ev.dateRange1 && ev.dateRange2 >= lookup.startstake){
            startDateUnderRangeCheck = true;
        }
        
        if((block.timestamp - lookup.startstake) >= ev.stakeTimeElapsed){
            stakeElapsedTimeCheck = true;
        }
        
        if(statusActiveCheck == true && periodChoosedCheck == true && startDateUnderRangeCheck == true && stakeElapsedTimeCheck == true){
            isEligible = true;
        }
        
        return isEligible;
    }
}