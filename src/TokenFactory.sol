// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Token} from "./Token.sol";
contract TokenFactory {
    address public owner;
    uint256 public creationFee;
    address[] public allTokens;
    mapping(address => bool) public isFactoryToken;
    mapping(address => address[]) public tokensByCreator;
    event TokenCreated(address indexed tokenAddress, address indexed creator, string name, string symbol, uint256 initialSupply);
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);
    error InsufficientFee(uint256 sent, uint256 required);
    error NotOwner();
    error ZeroAddress();
    error WithdrawFailed();
    error EmptyName();
    error EmptySymbol();
    modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }
    constructor(uint256 _creationFee) { owner = msg.sender; creationFee = _creationFee; }
    function createToken(string calldata _name, string calldata _symbol, uint8 _decimals, uint256 _initialSupply) external payable returns (address tokenAddress) {
        if (bytes(_name).length == 0) revert EmptyName();
        if (bytes(_symbol).length == 0) revert EmptySymbol();
        if (msg.value < creationFee) revert InsufficientFee(msg.value, creationFee);
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, _name, _symbol));
        Token token = new Token{salt: salt}(_name, _symbol, _decimals, _initialSupply);
        tokenAddress = address(token);
        token.transferOwnership(msg.sender);
        allTokens.push(tokenAddress);
        isFactoryToken[tokenAddress] = true;
        tokensByCreator[msg.sender].push(tokenAddress);
        emit TokenCreated(tokenAddress, msg.sender, _name, _symbol, _initialSupply);
        if (msg.value > creationFee) {
            uint256 refund = msg.value - creationFee;
            (bool success, ) = msg.sender.call{value: refund}("");
            if (!success) revert WithdrawFailed();
        }
    }
    function predictTokenAddress(address creator, string calldata _name, string calldata _symbol, uint8 _decimals, uint256 _initialSupply) external view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(creator, _name, _symbol));
        bytes memory bytecode = abi.encodePacked(type(Token).creationCode, abi.encode(_name, _symbol, _decimals, _initialSupply));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        return address(uint160(uint256(hash)));
    }
    function totalTokens() external view returns (uint256) { return allTokens.length; }
    function getTokensByCreator(address creator) external view returns (address[] memory) { return tokensByCreator[creator]; }
    function getTokensPaginated(uint256 offset, uint256 limit) external view returns (address[] memory tokens, uint256 total) {
        total = allTokens.length;
        if (offset >= total) return (new address[](0), total);
        uint256 end = offset + limit; if (end > total) end = total;
        uint256 length = end - offset;
        tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) tokens[i] = allTokens[offset + i];
    }
    function updateFee(uint256 _newFee) external onlyOwner { emit FeeUpdated(creationFee, _newFee); creationFee = _newFee; }
    function withdrawFees(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        if (!success) revert WithdrawFailed();
        emit FeesWithdrawn(to, balance);
    }
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
    receive() external payable {}
}
