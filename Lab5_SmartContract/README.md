# **ปฏิบัติการที่ 5 การเขียน smart contract**

**จากเกมเป่ายิ้งฉุบธรรมดา แปลงให้เป็นเกมเป่ายิ้งฉุบที่น่าสนใจมากขึ้น**

**[https://bigbangtheory.fandom.com/wiki/Rock,\_Paper,\_Scissors,\_Lizard,\_Spock](https://bigbangtheory.fandom.com/wiki/Rock,_Paper,_Scissors,_Lizard,_Spock)**

**[https://www.youtube.com/watch?v=x5Q6-wMx-K8](https://www.youtube.com/watch?v=x5Q6-wMx-K8)**

1. Requirements**ทำให้ contract ใช้งานได้ใหม่ เมื่อจ่ายรางวัลไปแล้ว**
2. อนุญาตให้คนที่จะเล่นเกมส์นี้ได้ต้องใช้ account จาก 4 account ต่อไปนี้เท่านั้น
   1. 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4
   2. 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2
   3. 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db
   4. 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB
3. ใช้ commit-reveal เพื่อซ่อนการเลือก เพื่อแก้ front-running
4. ต้องใช้ฟังก์ชั่นเกี่ยวกับเวลาเพื่อเปิดโอกาสให้มีการถอนเงินออกหลังจากระยะเวลาผ่านไประยะหนึ่ง

## **Setup & Modifier**

กำหนดให้ 0, 1, 2, 3, 4 แทน Rock, Paper, Scissors, Spock และ Lizard

```

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

```

ใส่ allowedAddresses กำหนดไปว่าจะรับ Transaction จาก Address 4 ตัวนี้เท่านั้น
แล้วตั้งให้เป็น modifer เพื่อบังคับฟังก์ชั่นให้ตรวจสอบว่าถูกเรียกโดยคนพวกนี้เท่านั้นหรือไม่

```

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

```

## ฟังก์ชั่นเพิ่มผู้เล่น

```

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

```

ผู้เล่นต้องทำการใส่ input ที่เป็นผลลัพธ์จากการเอา 00, 01, 02, 03 หรือ 04 ไปเข้าโปรแกรม choice_hiding_v2.ipynb
โดย choice_hiding_v2.ipynb หน้าตาแบบนี้

```

import random


# generate 31 random bytes
rand_num = random.getrandbits(256 - 8)
rand_bytes = hex(rand_num)

# choice: '00', '01', '02' (rock, paper, scissors)
# concatenate choice to rand_bytes to make 32 bytes data_input
choice = '00'
data_input = rand_bytes + choice
print(data_input)
print(len(data_input))
print()

# need padding if data_input has less than 66 symbols (< 32 bytes)
if len(data_input) < 66:
  print("Need padding.")
  data_input = data_input[0:2] + '0' * (66 - len(data_input)) + data_input[2:]
  assert(len(data_input) == 66)
else:
  print("Need no padding.")
print("Choice is", choice)
print("Use the following bytes32 as an input to the getHash function:", data_input)
print(len(data_input))

```

ตัวอย่าง
choice = '00'
พอคำนวน data_input = rand_bytes(31 bytes) + choice(1 byte)
จะได้ `0xb15806802200b99f97cd7ca3135403a0e87be8b068ca0d3b274edc765ae3f000`
เช็คความยาว แล้วเติม Padding
จะได้ `0xb15806802200b99f97cd7ca3135403a0e87be8b068ca0d3b274edc765ae3f000` เอาไปใส่ใน `getHash` function

```

    function getHash(bytes32 data) public pure returns(bytes32){
        return keccak256(abi.encodePacked(data));
    }

```

จะได้ `0x617f5cd344acf9f37ac85f4a19c7a34be7f8e2dd288ad689037113a55a183602` เพื่อเอาไปใส่ใน `commitMove`

## ฟังก์ชั่น commitMove

(คือ Commit ใน CommitReveal)

```

    // Commit ด้วยผลลัพธ์จาก Function getHash ที่รับ ผลลัพธ์ choice_hiding_v2 เป็น input
    function commitMove(bytes32 dataHash) public onlyAllowed {
        commits[msg.sender].commit = dataHash;
        commits[msg.sender].block = uint64(block.number);
        commits[msg.sender].revealed = false;
        emit MoveCommitted(msg.sender);
    }
    event MoveCommitted(address player);

```

## ฟังก์ชั่น revealMove

```

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

```

## ฟังก์ชั่น findWinner

* เล่นเกม Rock, Paper, Scissors, Lizard, Spock
  * แต่ละ Choice xx จะชนะ Choice xx + 2 และ xx + 4 เสมอ ดังนั้นจึงใช้การ Modulo 5 เพื่อหาความสัมพันธ์ว่าใครเป็นผู้ชนะได้
* ให้ Contract reset หลังจากจ่ายเงินแล้ว

```

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

```

## ฟังก์ชั่น withdrawIfNoOpponent

ใส่ฟังก์ชั่นที่ อนุญาตให้ถอนเงินหากไม่มีผู้เล่น join game เพิ่ม

```

    function withdrawIfNoOpponent() public onlyAllowed {
        require(numPlayer == 1, "Cannot withdraw, game in progress or no funds");
        require(block.timestamp > startTime + 5 minutes, "Must wait 5 minutes before withdrawing");

        address payable player0 = payable(players[0]);
        player0.transfer(reward);

        _resetGame();
    }


```

## ฟังก์ชั่น withdrawIfNoTimeout

ใส่ฟังก์ชั่นที่ อนุญาตให้ถอนเงินเมื่อผู้เล่นเข้ามา 2 คนแล้วถ้าเวลาผ่านไป 5 นาที แล้วผู้เล่นอีกคนไม่ยอม Commit

```

    function withdrawIfTimeout() public payable onlyAllowed {
        require(gameActive == true, "No game to withdraw");
        require(block.timestamp > startTime + 5 minutes, "You can only withdraw after 5 minutes if other player haven't made a move");

        for (uint i = 0; i < players.length; i++) {
            address payable player = payable(players[i]);
            player.transfer(reward / numPlayer);
        }
        _resetGame();
    }

```

## ฟังก์ชั่น Reset Game

```

    function _resetGame() private {
        numPlayer = 0;
        reward = 0;
        delete players;
        gameActive = false;

        emit GameReset();
    }
    event GameReset();

```
