// SPDX-License-Identifier: GPL-3.0

pragma solidity >= 0.7.0 <0.9.0;

import "./CommitReveal.sol";
import "./TimeUnit.sol";

contract RPS {

    uint public numPlayer = 0;
    uint public reward = 0;
    uint public startTime;
    bool public gameActive = false;

    struct Commit {
        bytes32 commit;
        uint64 block;
        bool revealed;
    }

    mapping (address => Commit) public commits;
    // 0 - Rock, 1 - Paper , 2 - Scissors, 3 - Spock, 4 - Lizard
    mapping (address => uint) public player_choices;

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
        // reward += 1 ether;
        players.push(msg.sender);

        numPlayer++;
        emit PlayerJoined(msg.sender);

        if (numPlayer == 2) {
            gameActive = true;
            startTime = block.timestamp;
        }
    }
    event PlayerJoined(address player);

    function isValidChoice(bytes32 data) public pure returns (bool) {
    bytes1 lastByte = bytes1(data << 248); // Extract the last byte
    return (lastByte == 0x00 ||
            lastByte == 0x01 ||
            lastByte == 0x02 ||
            lastByte == 0x03 ||
            lastByte == 0x04);
    }

    // Commit ด้วยผลลัพธ์จาก Function getHash ที่รับ ผลลัพธ์ choice_hiding_v2 เป็น input
    function commitMove(bytes32 dataHash) public onlyAllowed {
        commits[msg.sender].commit = dataHash;
        commits[msg.sender].block = uint64(block.number);
        commits[msg.sender].revealed = false;
        emit MoveCommitted(msg.sender);
    }
    event MoveCommitted(address player);

    function getLastByte(bytes32 data) private pure returns (uint8) {
        return uint8(data[31]); // Extracts the last byte and converts to uint8
    }

    function getHash(bytes32 data) public pure returns(bytes32){
        return keccak256(abi.encodePacked(data));
    }

    // Reveal โดยใส่ผลลัพธ์จาก choice_hiding_v2
    function revealMove (bytes32 Move) public onlyAllowed {
        require(isValidChoice(Move), "Invalid move: must be 00-04");

        require(commits[msg.sender].revealed == false, "RPS::revealMove: Move already revealed");
        commits[msg.sender].revealed= true;

        require(getHash(Move)==commits[msg.sender].commit,"CommitReveal::reveal: Revealed hash does not match commit");

        require(uint64(block.number)>commits[msg.sender].block,"CommitReveal::reveal: Reveal and commit happened on the same block");
        require(uint64(block.number) <= commits[msg.sender].block+250,"RPS::revealMove: Revealed too late");

        require(gameActive == true, "RPS::revealMove: Game is not active");
        
        player_choices[msg.sender] = getLastByte(Move);

        emit MoveRevealed(msg.sender, player_choices[msg.sender]);

        if ( commits[players[0]].revealed && commits[players[1]].revealed ) {
            _findWinner();
        }
    }
    event MoveRevealed(address player, uint choice);

    function _findWinner() private {
        uint p0Choice = player_choices[players[0]];
        uint p1Choice = player_choices[players[1]];
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);
        
        if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
            account1.transfer(reward);
            emit WinnerDeclared(account1, reward);
        } else if ((p1Choice + 1) % 5 == p0Choice || (p1Choice + 3) % 5 == p0Choice) {
            account0.transfer(reward);
            emit WinnerDeclared(account0, reward);    
        } else {
            account0.transfer(reward / 2);
            account1.transfer(reward / 2);
            emit WinnerDeclared(players[0], reward / 2);
            emit WinnerDeclared(players[1], reward / 2);
        }

        _resetGame();
    }
    event WinnerDeclared(address winner, uint amount);

    function withdrawIfNoOpponent() public onlyAllowed {
        require(numPlayer == 1, "Cannot withdraw, game in progress or no funds");
        require(block.timestamp > startTime + 5 minutes, "Must wait 5 minutes before withdrawing");
        
        address payable player0 = payable(players[0]);
        player0.transfer(reward);
        
        _resetGame();
    }

    function withdrawIfTimeout() public onlyAllowed {
        require(gameActive, "No game to withdraw from");
        require(block.timestamp > startTime + 5 minutes, "Cannot withdraw yet");

        if (commits[players[0]].revealed && !commits[players[1]].revealed) {
            payable(players[0]).transfer(reward);
        } else if (commits[players[1]].revealed && !commits[players[0]].revealed) {
            payable(players[1]).transfer(reward);
        } else {
            for (uint i = 0; i < players.length; i++) {
                address payable player = payable(players[i]);
                player.transfer(reward / numPlayer);
            }
        }
        _resetGame();
    }

    function _resetGame() private {
        numPlayer = 0;
        reward = 0;
        delete players;
        gameActive = false;

        emit GameReset();
    }
    event GameReset();
}