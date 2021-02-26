// SPDX-License-Identifier: MIT

/*
    ___       ___       ___       ___       ___       ___       ___       ___
   /\  \     /\__\     /\  \     /\  \     /\__\     /\  \     /\  \     /\__\
  /::\  \   /:/  /    /::\  \   /::\  \   /:/ _/_   /::\  \   /::\  \   |::L__L
 /::\:\__\ /:/__/    /::\:\__\ /:/\:\__\ /::-"\__\ /::\:\__\ /:/\:\__\ /::::\__\
 \:\::/  / \:\  \    \/\::/  / \:\ \/__/ \;:;-",-" \:\::/  / \:\/:/  / \;::;/__/
  \::/  /   \:\__\     /:/  /   \:\__\    |:|  |    \::/  /   \::/  /   |::|__|
   \/__/     \/__/     \/__/     \/__/     \|__|     \/__/     \/__/     \/__/

BlackBox - Perpetual Reflect Lottery

*/

pragma solidity ^0.6.12;

import "https://github.com/pancakeswap/pancake-swap-lib/blob/master/contracts/GSN/Context.sol";
import "https://github.com/pancakeswap/pancake-swap-lib/blob/master/contracts/token/BEP20/IBEP20.sol";
import "https://github.com/pancakeswap/pancake-swap-lib/blob/master/contracts/math/SafeMath.sol";
import "https://github.com/pancakeswap/pancake-swap-lib/blob/master/contracts/utils/Address.sol";
import "https://github.com/pancakeswap/pancake-swap-lib/blob/master/contracts/access/Ownable.sol";

contract BlackBox is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    string private constant NAME = "BlackBox";
    string private constant SYMBOL = "BBOX";
    uint8 private constant DECIMALS = 9;

    mapping(address => uint256) private rewards;
    mapping(address => uint256) private actual;
    mapping(address => mapping(address => uint256)) private allowances;

    mapping(address => bool) private excludedFromFees;
    mapping(address => bool) private excludedFromRewards;
    mapping(address => bool) private excludedFromBBOX;
    address[] private rewardExcluded;
    address[] private jacksInBBOX;

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant ACTUAL_TOTAL = 1_000_000 * 1e9;
    uint256 private rewardsTotal = (MAX - (MAX % ACTUAL_TOTAL));
    uint256 private holderFeeTotal;
    uint256 private BBOXFeeTotal;
    uint256 private lpFeeTotal;

    uint256 public taxPercentage = 5;
    uint256 public holderTaxAlloc = 2;
    uint256 public BBOXTaxAlloc = 8;
    uint256 public lpTaxAlloc;
    uint256 public totalTaxAlloc = BBOXTaxAlloc.add(holderTaxAlloc).add(lpTaxAlloc);
    uint256 public BBOXcapacity = 1000;

    address public BBOXAddress;
    address public lpStakingAddress;

    constructor(address _BBOXAddress) public {
        rewards[_BBOXAddress] = rewardsTotal;
        emit Transfer(address(0), _msgSender(), ACTUAL_TOTAL);

        BBOXAddress = _BBOXAddress;

        excludeFromRewards(_msgSender());
        excludeFromFees(_BBOXAddress);

        if (_BBOXAddress != _msgSender()) {
            excludeFromRewards(_BBOXAddress);
            excludeFromFees(_msgSender());
        }

        excludeFromFees(address(0x000000000000000000000000000000000000dEaD));
    }

    function name() external view override returns (string memory) {
        return NAME;
    }

    function symbol() external view override returns (string memory) {
        return SYMBOL;
    }

    function decimals() external view override returns (uint8) {
        return DECIMALS;
    }

    function totalSupply() external view override returns (uint256) {
        return ACTUAL_TOTAL;
    }

    function balanceOf(address _account) public view override returns (uint256) {
        if (excludedFromRewards[_account]) {
            return actual[_account];
        }
        return tokenWithRewards(rewards[_account]);
    }

    function getOwner() external view override returns (address) {
        return owner();
    }

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _transfer(_msgSender(), _recipient, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) public view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) public override returns (bool) {
        _approve(_msgSender(), _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _transfer(_sender, _recipient, _amount);
        _approve(_sender, _msgSender(), allowances[_sender][_msgSender()].sub(_amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public virtual returns (bool) {
        _approve(_msgSender(), _spender, allowances[_msgSender()][_spender].add(_addedValue));
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), _spender, allowances[_msgSender()][_spender].sub(_subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromRewards(address _account) external view returns (bool) {
        return excludedFromRewards[_account];
    }

    function isExcludedFromFees(address _account) external view returns (bool) {
        return excludedFromFees[_account];
    }

    function isExcludedFromBBOX(address _account) external view returns (bool) {
        return excludedFromBBOX[_account];
    }

    function totalFees() external view returns (uint256) {
        return holderFeeTotal.add(BBOXFeeTotal).add(lpFeeTotal);
    }

    function totalHolderFees() external view returns (uint256) {
        return holderFeeTotal;
    }

    function totalBBOXFees() external view returns (uint256) {
        return BBOXFeeTotal;
    }

    function totalLpFees() external view returns (uint256) {
        return lpFeeTotal;
    }

    function distribute(uint256 _actualAmount) public {
        address sender = _msgSender();
        require(!excludedFromRewards[sender], "Excluded addresses cannot call this function");

        (uint256 rewardAmount, , , , ) = _getValues(_actualAmount);
        rewards[sender] = rewards[sender].sub(rewardAmount);
        rewardsTotal = rewardsTotal.sub(rewardAmount);
        holderFeeTotal = holderFeeTotal.add(_actualAmount);
    }

    function excludeFromFees(address _account) public onlyOwner() {
        require(!excludedFromFees[_account], "Account is already excluded from fee");
        excludedFromFees[_account] = true;
        excludedFromBBOX[_account] = false;
    }

    function includeInFees(address _account) public onlyOwner() {
        require(excludedFromFees[_account], "Account is already included in fee");
        excludedFromFees[_account] = false;
        excludedFromBBOX[_account] = true;
    }

    function excludeFromRewards(address _account) public onlyOwner() {
        require(!excludedFromRewards[_account], "Account is already excluded from reward");

        if (rewards[_account] > 0) {
            actual[_account] = tokenWithRewards(rewards[_account]);
        }

        excludedFromRewards[_account] = true;
        excludedFromBBOX[_account] = true;
        rewardExcluded.push(_account);
    }

    function includeInRewards(address _account) public onlyOwner() {
        require(excludedFromRewards[_account], "Account is already included in rewards");

        for (uint256 i = 0; i < rewardExcluded.length; i++) {
            if (rewardExcluded[i] == _account) {
                rewardExcluded[i] = rewardExcluded[rewardExcluded.length - 1];
                actual[_account] = 0;
                excludedFromRewards[_account] = false;
                excludedFromBBOX[_account] = false;
                rewardExcluded.pop();
                break;
            }
        }
    }

    function rand(uint256 maxNum) private view returns(uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(
            block.timestamp + block.difficulty +
            ((uint256(keccak256(abi.encodePacked(block.coinbase)))) / (block.timestamp)) +
            block.gaslimit +
            ((uint256(keccak256(abi.encodePacked(msg.sender)))) / (block.timestamp)) +
            block.number
        )));

        return (seed - ((seed / maxNum) * maxNum));
    }

    function pushJacksInBBOX(address _sender, address _recipient) private {
        require(_sender != address(0), "Cannot add zero address");
        require(_recipient != address(0), "Cannot add zero address");

        if (excludedFromBBOX[_sender] && !excludedFromBBOX[_recipient]) {
            jacksInBBOX.push(_recipient);
        }
        if (balanceOf(BBOXAddress) >= BBOXcapacity * 1e9) {
            _transfer(BBOXAddress, jacksInBBOX[rand(jacksInBBOX.length)], balanceOf(BBOXAddress));
            while (jacksInBBOX.length > 0) {
                jacksInBBOX.pop();
            }
        }
    }

    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "ERC20: transfer from the zero address");
        require(_recipient != address(0), "ERC20: transfer to the zero address");
        require(_amount > 0, "Transfer amount must be greater than zero");

        uint256 currentTaxPercentage = taxPercentage;
        if (excludedFromFees[_sender] || excludedFromFees[_recipient]) {
            taxPercentage = 0;
        } else {
            uint256 fee = _getFee(_amount);
            uint256 BBOXFee = _getBBOXFee(fee);
            uint256 lpFee = _getLpFee(fee);

            _updateBBOXFee(BBOXFee);
            _updateLpFee(lpFee);
        }

        if (excludedFromRewards[_sender] && !excludedFromRewards[_recipient]) {
            _transferWithoutSenderRewards(_sender, _recipient, _amount);
        } else if (!excludedFromRewards[_sender] && excludedFromRewards[_recipient]) {
            _transferWithRecipientRewards(_sender, _recipient, _amount);
        } else if (!excludedFromRewards[_sender] && !excludedFromRewards[_recipient]) {
            _transferWithRewards(_sender, _recipient, _amount);
        } else if (excludedFromRewards[_sender] && excludedFromRewards[_recipient]) {
            _transferWithoutRewards(_sender, _recipient, _amount);
        } else {
            _transferWithRewards(_sender, _recipient, _amount);
        }

        if (currentTaxPercentage != taxPercentage) {
            taxPercentage = currentTaxPercentage;
        }
        pushJacksInBBOX(_sender, _recipient);
    }

    function _transferWithRewards(address _sender, address _recipient, uint256 _actualAmount) private {
        (uint256 rewardAmount, uint256 rewardTransferAmount, uint256 rewardFee, uint256 actualTransferAmount, uint256 actualFee) = _getValues(_actualAmount);

        rewards[_sender] = rewards[_sender].sub(rewardAmount);
        rewards[_recipient] = rewards[_recipient].add(rewardTransferAmount);
        _updateHolderFee(rewardFee, actualFee);
        emit Transfer(_sender, _recipient, actualTransferAmount);
    }

    function _transferWithRecipientRewards(address _sender, address _recipient, uint256 _actualAmount) private {
        (uint256 rewardAmount, uint256 rewardTransferAmount, uint256 rewardFee, uint256 actualTransferAmount, uint256 actualFee) = _getValues(_actualAmount);

        rewards[_sender] = rewards[_sender].sub(rewardAmount);
        actual[_recipient] = actual[_recipient].add(actualTransferAmount);
        rewards[_recipient] = rewards[_recipient].add(rewardTransferAmount);
        _updateHolderFee(rewardFee, actualFee);
        emit Transfer(_sender, _recipient, actualTransferAmount);
    }

    function _transferWithoutSenderRewards(address _sender, address _recipient, uint256 _actualAmount) private {
        (uint256 rewardAmount, uint256 rewardTransferAmount, uint256 rewardFee, uint256 actualTransferAmount, uint256 actualFee) = _getValues(_actualAmount);

        actual[_sender] = actual[_sender].sub(_actualAmount);
        rewards[_sender] = rewards[_sender].sub(rewardAmount);
        rewards[_recipient] = rewards[_recipient].add(rewardTransferAmount);
        _updateHolderFee(rewardFee, actualFee);
        emit Transfer(_sender, _recipient, actualTransferAmount);
    }

    function _transferWithoutRewards(address _sender, address _recipient, uint256 _actualAmount) private {
        (uint256 rewardAmount, uint256 rewardTransferAmount, uint256 rewardFee, uint256 actualTransferAmount, uint256 actualFee) = _getValues(_actualAmount);

        actual[_sender] = actual[_sender].sub(_actualAmount);
        rewards[_sender] = rewards[_sender].sub(rewardAmount);
        actual[_recipient] = actual[_recipient].add(actualTransferAmount);
        rewards[_recipient] = rewards[_recipient].add(rewardTransferAmount);
        _updateHolderFee(rewardFee, actualFee);
        emit Transfer(_sender, _recipient, actualTransferAmount);
    }

    function _updateHolderFee(uint256 _rewardFee, uint256 _actualFee) private {
        rewardsTotal = rewardsTotal.sub(_rewardFee);
        holderFeeTotal = holderFeeTotal.add(_actualFee);
    }

    function _updateBBOXFee(uint256 _BBOXFee) private {
        if (BBOXAddress == address(0)) {
            return;
        }

        uint256 rewardsRate = _getRewardsRate();
        uint256 rewardBBOXFee = _BBOXFee.mul(rewardsRate);
        BBOXFeeTotal = BBOXFeeTotal.add(_BBOXFee);

        rewards[BBOXAddress] = rewards[BBOXAddress].add(rewardBBOXFee);
        if (excludedFromRewards[BBOXAddress]) {
            actual[BBOXAddress] = actual[BBOXAddress].add(_BBOXFee);
        }
    }

    function _updateLpFee(uint256 _lpFee) private {
        if (lpStakingAddress == address(0)) {
            return;
        }

        uint256 rewardsRate = _getRewardsRate();
        uint256 rewardLpFee = _lpFee.mul(rewardsRate);
        lpFeeTotal = lpFeeTotal.add(_lpFee);

        rewards[lpStakingAddress] = rewards[lpStakingAddress].add(rewardLpFee);
        if (excludedFromRewards[lpStakingAddress]) {
            actual[lpStakingAddress] = actual[lpStakingAddress].add(_lpFee);
        }
    }

    function rewardsFromToken(uint256 _actualAmount, bool _deductTransferFee) public view returns (uint256) {
        require(_actualAmount <= ACTUAL_TOTAL, "Amount must be less than supply");
        if (!_deductTransferFee) {
            (uint256 rewardAmount, , , , ) = _getValues(_actualAmount);
            return rewardAmount;
        } else {
            (, uint256 rewardTransferAmount, , , ) = _getValues(_actualAmount);
            return rewardTransferAmount;
        }
    }

    function tokenWithRewards(uint256 _rewardAmount) public view returns (uint256) {
        require(_rewardAmount <= rewardsTotal, "Amount must be less than total rewards");
        uint256 rewardsRate = _getRewardsRate();
        return _rewardAmount.div(rewardsRate);
    }

    function _getValues(uint256 _actualAmount) private view returns (uint256, uint256, uint256, uint256, uint256) {
        (uint256 actualTransferAmount, uint256 actualFee) = _getActualValues(_actualAmount);
        uint256 rewardsRate = _getRewardsRate();
        (uint256 rewardAmount, uint256 rewardTransferAmount, uint256 rewardFee) = _getRewardValues(_actualAmount, actualFee, rewardsRate);

        return (rewardAmount, rewardTransferAmount, rewardFee, actualTransferAmount, actualFee);
    }

    function _getActualValues(uint256 _actualAmount) private view returns (uint256, uint256) {
        uint256 actualFee = _getFee(_actualAmount);
        uint256 actualHolderFee = _getHolderFee(actualFee);
        uint256 actualTransferAmount = _actualAmount.sub(actualFee);
        return (actualTransferAmount, actualHolderFee);
    }

    function _getRewardValues(uint256 _actualAmount, uint256 _actualHolderFee, uint256 _rewardsRate) private view returns (uint256, uint256, uint256) {
        uint256 actualFee = _getFee(_actualAmount).mul(_rewardsRate);
        uint256 rewardAmount = _actualAmount.mul(_rewardsRate);
        uint256 rewardTransferAmount = rewardAmount.sub(actualFee);
        uint256 rewardFee = _actualHolderFee.mul(_rewardsRate);
        return (rewardAmount, rewardTransferAmount, rewardFee);
    }

    function _getRewardsRate() private view returns (uint256) {
        (uint256 rewardsSupply, uint256 actualSupply) = _getCurrentSupply();
        return rewardsSupply.div(actualSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rewardsSupply = rewardsTotal;
        uint256 actualSupply = ACTUAL_TOTAL;

        for (uint256 i = 0; i < rewardExcluded.length; i++) {
            if (rewards[rewardExcluded[i]] > rewardsSupply || actual[rewardExcluded[i]] > actualSupply) {
                return (rewardsTotal, ACTUAL_TOTAL);
            }

            rewardsSupply = rewardsSupply.sub(rewards[rewardExcluded[i]]);
            actualSupply = actualSupply.sub(actual[rewardExcluded[i]]);
        }

        if (rewardsSupply < rewardsTotal.div(ACTUAL_TOTAL)) {
            return (rewardsTotal, ACTUAL_TOTAL);
        }

        return (rewardsSupply, actualSupply);
    }

    function _getFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(taxPercentage).div(100);
    }

    function _getHolderFee(uint256 _tax) private view returns (uint256) {
        return _tax.mul(holderTaxAlloc).div(totalTaxAlloc);
    }

    function _getBBOXFee(uint256 _tax) private view returns (uint256) {
        return _tax.mul(BBOXTaxAlloc).div(totalTaxAlloc);
    }

    function _getLpFee(uint256 _tax) private view returns (uint256) {
        return _tax.mul(lpTaxAlloc).div(totalTaxAlloc);
    }

    function getBBOXPoolAdds() public view returns (address[] memory) {
        return jacksInBBOX;
    }

    function setTaxPercentage(uint256 _taxPercentage) external onlyOwner {
        require(_taxPercentage >= 1 && _taxPercentage <= 10, "Value is outside of range 1-10");
        taxPercentage = _taxPercentage;
    }

    function setTaxAllocations(uint256 _holderTaxAlloc, uint256 _BBOXTaxAlloc, uint256 _lpTaxAlloc) external onlyOwner {
        totalTaxAlloc = _holderTaxAlloc.add(_BBOXTaxAlloc).add(_lpTaxAlloc);

        require(_holderTaxAlloc <= 10 && _holderTaxAlloc > 0, "_holderTaxAlloc is outside of range 1-10");
        require(_lpTaxAlloc <= 10, "_lpTaxAlloc is outside of range 5-10");
        require(_BBOXTaxAlloc <= 10, "_BBOXTaxAlloc is greater than 10");

        holderTaxAlloc = _holderTaxAlloc;
        BBOXTaxAlloc = _BBOXTaxAlloc;
        lpTaxAlloc = _lpTaxAlloc;
    }

    function setBBOXAddress(address _BBOXAddress) external onlyOwner {
        BBOXAddress = _BBOXAddress;
        excludeFromRewards(_BBOXAddress);
        excludeFromFees(_BBOXAddress);
    }

    function setBBOXcapacity(uint256 capacity) external onlyOwner {
        BBOXcapacity = capacity;
    }

    function setLpStakingAddress(address _lpStakingAddress) external onlyOwner {
        lpStakingAddress = _lpStakingAddress;
    }
}
