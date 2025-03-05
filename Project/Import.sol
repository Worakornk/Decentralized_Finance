// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// import Foo.sol from current directory
import "./Foo.sol";
import "./TimeUnit.sol";

// import {symbol1 as alias, symbol2} from "filename";
import {Unauthorized, add as func, Point} from "./Foo.sol";

contract Import {
    // Initialize Foo.sol
    Foo public foo = new Foo();

    // Initialize TimeUnit.sol
    TimeUnit public timeUnit = new TimeUnit();

    constructor () {
        timeUnit.setStartTime();
    }

    // Test Foo.sol by getting its name.
    function getFooName() public view returns (string memory) {
        return foo.name();
    }

    function delayGetFooName() public view returns (string memory) {
        if (timeUnit.elapsedSeconds() > 30) {
            return foo.name();
        }
        return "";
    }

}

