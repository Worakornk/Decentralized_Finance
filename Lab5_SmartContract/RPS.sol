
// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CommitReveal.sol";
import "./TimeUnit.sol";

contract RPS is ReentrancyGuard {
    uint public numPlayer = 0;
    uint public reward = 0;
    uint public startTime;
    bool public gameActive = false;

    // 0 - Rock, 1 - Paper , 2 - Scissors, 3 - Spock, 4 - Lizard
    mapping (address => bytes32) public commits; 
    mapping (address => uint) public player_choices; 
    mapping(address => bool) public revealed;

    address[] public players;
    address[] private allowedAddresses = [
        0x5B38Da6a701c568545dCfcB03FcB875f56beddC4,
        0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,
        0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db,
        0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB
    ];
    
    modifier onlyAllowed() {
        bool isAllowed = false;
        for (uint i = 0; i < allowedAddresses.length; i++) {
            if (msg.sender == allowedAddresses[i]) {
                isAllowed = true;
                break;
            }
        }
        require(isAllowed, "Access denied: You are not an authorized user");
        _;
    }

    function addPlayer() public payable onlyAllowed {
        require(numPlayer < 2, "Maximum Players Reached");
        require(gameActive == false, "Game already in progress");

        if (numPlayer > 0) {
            require(msg.sender != players[0], "You are already in the game");
        }

        require(msg.value == 1 ether, "Entry fee is 1 ether");
        reward += msg.value;
        players.push(msg.sender);
        numPlayer++;

        if (numPlayer == 2) {
            gameActive = true;
            startTime = block.timestamp;
        }
    }

    function commitMove(bytes32 hashedMove) public onlyAllowed {
        require(gameActive == true, "Game is not active");
        require(numPlayer == 2, "Not enough player");
        require(commits[msg.sender] == 0, "Move already commited");

        commits[msg.sender] = hashedMove;
    }

    function revealMove (uint choice, string memory nonce) public onlyAllowed {
        require(gameActive == true, "Game is not active");
        require(commits[msg.sender] != 0, "No commit has been made);");
        require(revealed[msg.sender] == false, "Move already revealed");
        require(choice >= 0 && choice <= 4, "Invalid Input");

        bytes32 CheckHash = keccak256(abi.encodePacked(choice, nonce));
        require(CheckHash == commits[msg.sender], "Invalid Reveal");
        

        player_choices[msg.sender] = choice;
        revealed[msg.sender] = true;

        if (revealed[players[0]] && revealed[players[1]]) {
            _findWinner();
        }
    }

    function _findWinner() private nonReentrant {
        uint p0Choice = player_choices[players[0]];
        uint p1Choice = player_choices[players[1]];
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);
        
        if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
            account1.transfer(reward);
        } else if ((p1Choice + 1) % 5 == p0Choice || (p1Choice + 3) % 5 == p0Choice) {
            account0.transfer(reward);    
        } else {
            account0.transfer(reward / 2);
            account1.transfer(reward / 2);
        }

        _resetGame();
    }

    function withdrawIfTimeout() public onlyAllowed {
        require(gameActive == true, "No game to withdraw");
        require(block.timestamp > startTime + 5 minutes, "You can only withdraw after 5 minutes if other player haven't make a move");

        for (uint i = 0; i < players.length; i++) {
            address payable player = payable(players[i]);
            if (revealed[player] == false) {
                player.transfer(1 ether);
            }
        }
    }

    function _resetGame() private {
        numPlayer = 0;
        reward = 0;
        delete players;
        gameActive = false;
    }
}