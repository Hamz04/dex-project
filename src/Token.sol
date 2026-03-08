// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
contract Token {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error InsufficientBalance(address account, uint256 balance, uint256 needed);
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ZeroAddress();
    error NotOwner();
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply) {
        name = _name; symbol = _symbol; decimals = _decimals; owner = msg.sender;
        if (_initialSupply > 0) { _mint(msg.sender, _initialSupply * 10 ** _decimals); }
    }
    function transfer(address to, uint256 amount) external returns (bool) { _transfer(msg.sender, to, amount); return true; }
    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 ca = allowance[from][msg.sender];
        if (ca != type(uint256).max) {
            if (ca < amount) revert InsufficientAllowance(msg.sender, ca, amount);
            unchecked { allowance[from][msg.sender] = ca - amount; }
        }
        _transfer(from, to, amount);
        return true;
    }
    function mint(address to, uint256 amount) external onlyOwner { _mint(to, amount); }
    function burn(uint256 amount) external { _burn(msg.sender, amount); }
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 ca = allowance[msg.sender][spender];
        if (ca < subtractedValue) revert InsufficientAllowance(msg.sender, ca, subtractedValue);
        unchecked { allowance[msg.sender][spender] = ca - subtractedValue; }
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }
    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        uint256 fb = balanceOf[from];
        if (fb < amount) revert InsufficientBalance(from, fb, amount);
        unchecked { balanceOf[from] = fb - amount; balanceOf[to] += amount; }
        emit Transfer(from, to, amount);
    }
    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount; balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    function _burn(address from, uint256 amount) internal {
        uint256 fb = balanceOf[from];
        if (fb < amount) revert InsufficientBalance(from, fb, amount);
        unchecked { balanceOf[from] = fb - amount; totalSupply -= amount; }
        emit Transfer(from, address(0), amount);
    }
}
