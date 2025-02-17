// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../../../ExodiaAccessControlInitializable.sol";

import "../IPriceOracle.sol";
import "../../../interfaces/IBalV2PriceOracle.sol";
import "../../../../interfaces/IBPoolV2.sol";
import "../../../../interfaces/IBVaultV2.sol";
import "../../../../interfaces/IERC20.sol";

contract BalancerV2PriceOracle is IPriceOracle, ExodiaAccessControlInitializable {
    using SafeMath for uint256;

    uint256 public constant VERSION = 2022022201;
    address public constant FTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    address public vault;
    uint256 public minimumUpdateInterval = 5 minutes;
    mapping(address => IPriceOracle) public denominatedOracles; // token => denominated oracle
    mapping(address => address) public tokenPools; // token => balancer pool

    event SetTokenOracle(
        address indexed token,
        address indexed tokenPool,
        address indexed denominatedOracle
    );

    /**
     * @dev sets up the Price Oracle
     * @param _roles exodia roles address
     * @param _vault balancer vault address
     * @param _minimumUpdateInterval how often to permit updates to the TWAP (seconds)
     *                               If set to 0, will use the default of 5 minutes
     */
    function initialize(
        address _roles,
        address _vault,
        uint256 _minimumUpdateInterval
    ) public initializer {
        require(_vault != address(0), "vault cannot be null address");

        ExodiaAccessControlInitializable.initializeAccessControl(_roles);

        vault = _vault;
        if (_minimumUpdateInterval != 0) {
            minimumUpdateInterval = _minimumUpdateInterval;
        }
    }

    /**
     * @dev add/update token oracle setting
     */
    function setTokenOracle(
        address _token,
        address _tokenPool,
        address _denominatedOracle
    ) external onlyArchitect {
        bytes32 poolId = IBPoolV2(_tokenPool).getPoolId();
        (IERC20[] memory tokens, , ) = IBVaultV2(vault).getPoolTokens(poolId);

        require(tokens.length == 2, "INVALID POOL");
        require(
            _token != FTM &&
                (_token == address(tokens[0]) || _token == address(tokens[1])),
            "INVALID TOKENS"
        );
        require(
            _denominatedOracle != address(0) ||
                FTM == address(tokens[0]) ||
                FTM == address(tokens[1])
        );

        denominatedOracles[_token] = IPriceOracle(_denominatedOracle);
        tokenPools[_token] = _tokenPool;

        emit SetTokenOracle(_token, _tokenPool, _denominatedOracle);
    }

    /****** OPERATIONAL METHODS ******/

    /**
     * @dev returns the TWAP for the provided pair as of the last update
     */
    function getSafePrice(address _token) public view returns (uint256 price) {
        require(tokenPools[_token] != address(0), "UNSUPPORTED");

        IBalV2PriceOracle.OracleAverageQuery[]
            memory query = new IBalV2PriceOracle.OracleAverageQuery[](1);
        query[0] = IBalV2PriceOracle.OracleAverageQuery(
            IBalV2PriceOracle.TWAP_VALUE.PAIR_PRICE,
            minimumUpdateInterval,
            10
        );
        uint256[] memory prices = IBalV2PriceOracle(tokenPools[_token])
            .getTimeWeightedAverage(query);
        uint256 tokenPairPrice = prices[0];

        bytes32 poolId = IBPoolV2(tokenPools[_token]).getPoolId();
        (IERC20[] memory tokens, , ) = IBVaultV2(vault).getPoolTokens(poolId);

        if (_token == address(tokens[0])) {
            price =
                (_getTokenSafePrice(denominatedOracles[_token], tokens[1]) * (10**18)) /
                tokenPairPrice;
        } else if (_token == address(tokens[1])) {
            price =
                (_getTokenSafePrice(denominatedOracles[_token], tokens[0]) *
                    tokenPairPrice) /
                (10**18);
        }
    }

    /**
     * @dev returns the current "unsafe" price that can be easily manipulated
     */
    function getCurrentPrice(address _token) external view returns (uint256 price) {
        require(tokenPools[_token] != address(0), "UNSUPPORTED");

        bytes32 poolId = IBPoolV2(tokenPools[_token]).getPoolId();
        uint256[] memory weights = IBPoolV2(tokenPools[_token]).getNormalizedWeights();
        (IERC20[] memory tokens, uint256[] memory balances, ) = IBVaultV2(vault)
            .getPoolTokens(poolId);

        if (_token == address(tokens[0])) {
            price = _tokenPriceFromWeights(
                tokens[0],
                tokens[1],
                balances[0],
                balances[1],
                weights[0],
                weights[1]
            );
        } else if (_token == address(tokens[1])) {
            price = _tokenPriceFromWeights(
                tokens[1],
                tokens[0],
                balances[1],
                balances[0],
                weights[1],
                weights[0]
            );
        }
    }

    /**
     * @dev updates the TWAP (if enough time has lapsed) and returns the current safe price
     */
    function updateSafePrice(address _token) external returns (uint256) {
        return getSafePrice(_token);
    }

    // internal functions

    function _getTokenSafePrice(IPriceOracle oracle, IERC20 token)
        internal
        view
        returns (uint256 price)
    {
        price = 10**18;
        if (FTM != address(token)) {
            price = IPriceOracle(oracle).getSafePrice(address(token));
        }
    }

    function _getTokenCurrentPrice(IPriceOracle oracle, IERC20 token)
        internal
        view
        returns (uint256 price)
    {
        price = 10**18;
        if (FTM != address(token)) {
            price = IPriceOracle(oracle).getCurrentPrice(address(token));
        }
    }

    /**
     * @dev return token price (token0/token1)
     */
    function _tokenPriceFromWeights(
        IERC20 token0,
        IERC20 token1,
        uint256 balance0,
        uint256 balance1,
        uint256 weight0,
        uint256 weight1
    ) internal view returns (uint256) {
        uint256 pairTokenPrice = _getTokenCurrentPrice(
            IPriceOracle(denominatedOracles[address(token0)]),
            token1
        );

        // price = balance1 / balance0 * weight0 / weight1 * usdPrice1

        // in denominated token price decimals
        uint256 assetValue = (balance1 * pairTokenPrice) / (10**token1.decimals());
        // in denominated token price decimals
        return (assetValue * weight0 * (10**token0.decimals())) / weight1 / balance0;
    }
}
