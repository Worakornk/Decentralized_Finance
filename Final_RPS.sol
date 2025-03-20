// SPDX-License-Identifier: GPL-3.0
pragma solidity >= 0.7.0 <0.9.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract RPS {
    IERC20 public token;
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
    mapping (address => uint) public player_choices;
    address[] public players;

    uint256 public constant entryFee = 0.000001 ether;
    uint256 public constant revealTimeout = 5 minutes;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    function addPlayer() public {
        require(numPlayer < 2, "Maximum Players Reached");
        require(!gameActive, "Game already in progress");

        if (numPlayer > 0) {
            require(msg.sender != players[0], "You are already in the game");
        }

        require(token.allowance(msg.sender, address(this)) >= entryFee, "Not enough allowance");
        require(token.transferFrom(msg.sender, address(this), entryFee), "Token transfer failed");

        players.push(msg.sender);
        numPlayer++;
        reward += entryFee;

        emit PlayerJoined(msg.sender);

        if (numPlayer == 2) {
            gameActive = true;
            startTime = block.timestamp;
        }
    }
    event PlayerJoined(address player);

    function isValidChoice(bytes32 data) public pure returns (bool) {
        bytes1 lastByte = bytes1(data << 248);
        return (lastByte == 0x00 ||
                lastByte == 0x01 ||
                lastByte == 0x02 ||
                lastByte == 0x03 ||
                lastByte == 0x04);
    }

    function commitMove(bytes32 dataHash) public {
        require(gameActive, "Game is not active");
        commits[msg.sender] = Commit({
            commit: dataHash,
            block: uint64(block.number),
            revealed: false
        });

        emit MoveCommitted(msg.sender);
    }
    event MoveCommitted(address player);

    function getLastByte(bytes32 data) private pure returns (uint8) {
        return uint8(data[31]);
    }

    function getHash(bytes32 data) public pure returns(bytes32) {
        return keccak256(abi.encodePacked(data));
    }

    function revealMove(bytes32 move) public {
        require(gameActive, "Game is not active");
        require(isValidChoice(move), "Invalid move");
        require(!commits[msg.sender].revealed, "Move already revealed");
        require(getHash(move) == commits[msg.sender].commit, "Hash does not match commit");
        require(uint64(block.number) > commits[msg.sender].block, "Reveal and commit happened on the same block");
        require(uint64(block.number) <= commits[msg.sender].block + 250, "Revealed too late");

        commits[msg.sender].revealed = true;
        player_choices[msg.sender] = getLastByte(move);

        emit MoveRevealed(msg.sender, player_choices[msg.sender]);

        if (commits[players[0]].revealed && commits[players[1]].revealed) {
            _findWinner();
        }
    }
    event MoveRevealed(address player, uint choice);

    function _findWinner() private {
        uint p0Choice = player_choices[players[0]];
        uint p1Choice = player_choices[players[1]];
        address winner;

        if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
            winner = players[1];
        } else if ((p1Choice + 1) % 5 == p0Choice || (p1Choice + 3) % 5 == p0Choice) {
            winner = players[0];
        }

        if (winner != address(0)) {
            require(token.transfer(winner, reward), "Reward transfer failed");
            emit WinnerDeclared(winner, reward);
        } else {
            require(token.transfer(players[0], reward / 2), "Split reward failed");
            require(token.transfer(players[1], reward / 2), "Split reward failed");
            emit WinnerDeclared(players[0], reward / 2);
            emit WinnerDeclared(players[1], reward / 2);
        }

        _resetGame();
    }
    event WinnerDeclared(address winner, uint amount);

    function withdrawIfTimeout() public {
        require(gameActive, "No active game");
        require(block.timestamp > startTime + revealTimeout, "Cannot withdraw yet");

        if (commits[players[0]].revealed && !commits[players[1]].revealed) {
            require(token.transfer(players[0], reward), "Forced withdrawal failed");
        } else if (commits[players[1]].revealed && !commits[players[0]].revealed) {
            require(token.transfer(players[1], reward), "Forced withdrawal failed");
        } else {
            require(token.transfer(msg.sender, reward), "Anyone can withdraw due to timeout");
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
