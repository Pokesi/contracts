// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../ExodiaAccessControlInitializable.sol";

import "./adapters/IPriceOracle.sol";
import "./IPriceProvider.sol";

contract PriceProvider is IPriceProvider, ExodiaAccessControlInitializable {
    using SafeMath for uint256;

    event SetTokenOracle(address token, address oracle);

    uint256 public constant VERSION = 2022030201;

    mapping(address => address) public priceOracle;

    /**
     * @dev sets up the Price Oracle
     * @param _roles exodia roles address
     */
    function initialize(address _roles) public initializer {
        ExodiaAccessControlInitializable.initializeAccessControl(_roles);
    }

    function setTokenOracle(address token, address oracle) external onlyArchitect {
        priceOracle[token] = oracle;

        emit SetTokenOracle(token, oracle);
    }

    function getSafePrice(address token) external view override returns (uint256) {
        require(priceOracle[token] != address(0), "UNSUPPORTED");

        return IPriceOracle(priceOracle[token]).getSafePrice(token);
    }

    function getCurrentPrice(address token) external view override returns (uint256) {
        require(priceOracle[token] != address(0), "UNSUPPORTED");

        return IPriceOracle(priceOracle[token]).getCurrentPrice(token);
    }

    function updateSafePrice(address token) external override returns (uint256) {
        require(priceOracle[token] != address(0), "UNSUPPORTED");

        return IPriceOracle(priceOracle[token]).updateSafePrice(token);
    }
}
