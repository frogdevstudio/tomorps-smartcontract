pragma solidity >=0.4.21 <0.6.0;

contract AccessControl {
     /// @dev Emited when contract is upgraded - See README.md for updgrade plan
    event ContractUpgrade(address newContract);

    // The addresses of the accounts (or contracts) that can execute actions within each roles.
    address public ceoAddress;

    uint public totalTipForDeveloper = 0;

    // @dev Keeps track whether the contract is paused. When that is true, most actions are blocked
    bool public paused = false;

    /// @dev Access modifier for CEO-only functionality
    modifier onlyCEO() {
        require(msg.sender == ceoAddress, "You're not a CEO!");
        _;
    }

    /// @dev Wrong send eth! It's will tip for developer
    function () external payable{
        totalTipForDeveloper = totalTipForDeveloper + msg.value;
    }

    /// @dev Add tip for developer
    /// @param valueTip The value of tip
    function addTipForDeveloper(uint valueTip) internal {
        totalTipForDeveloper += valueTip;
    }

    /// @dev Developer can withdraw tip.
    function withdrawTipForDeveloper() external onlyCEO {
        require(totalTipForDeveloper > 0, "Need more tip to withdraw!");
        msg.sender.transfer(totalTipForDeveloper);
        totalTipForDeveloper = 0;
    }

    /// @dev Assigns a new address to act as the CEO. Only available to the current CEO.
    /// @param _newCEO The address of the new CEO
    function setCEO(address _newCEO) external onlyCEO {
        require(_newCEO != address(0), "Address to set CEO wrong!");

        ceoAddress = _newCEO;
    }

    /*Pausable functionality adapted from OpenZeppelin */

    /// @dev Modifier to allow actions only when the contract IS NOT paused
    modifier whenNotPaused() {
        require(!paused, "Paused!");
        _;
    }

    /// @dev Modifier to allow actions only when the contract IS paused
    modifier whenPaused {
        require(paused, "Not paused!");
        _;
    }

    /// @dev Called by any "C-level" role to pause the contract. Used only when
    ///  a bug or exploit is detected and we need to limit damage.
    function pause() external onlyCEO whenNotPaused {
        paused = true;
    }

    /// @dev Unpauses the smart contract. Can only be called by the CEO, since
    ///  one reason we may pause the contract is when CFO or COO accounts are
    ///  compromised.
    /// @notice This is public rather than external so it can be called by
    ///  derived contracts.
    function unpause() public onlyCEO whenPaused {
        // can't unpause if contract was upgraded
        paused = false;
    }
}