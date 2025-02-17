import hre from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

import { EXODIA_ROLES_DID } from "../../deploy/38_deployExodiaRoles";
import { BALANCER_V2_PRICE_ORACLE_DID } from "../../deploy/42_deployBalancerV2PriceOracle";
import { PRICE_PROVIDER_DID } from "../../deploy/44_deployPriceProvider";
import { externalAddressRegistry } from "../../packages/sdk/contracts";
import {
    IExodiaContractsRegistry,
    IExternalContractsRegistry,
} from "../../packages/sdk/contracts/exodiaContracts";
import { IExtendedHRE } from "../../packages/HardhatRegistryExtension/ExtendedHRE";
import { ZERO_ADDRESS } from "../../packages/utils/utils";
import {
    BalancerV2PriceOracle,
    ChainlinkPriceOracle__factory,
    ChainlinkPriceOracle,
    ExodiaRoles,
    ExodiaRoles__factory,
    PriceProvider,
    PriceProvider__factory,
} from "../../packages/sdk/typechain";

const xhre = hre as IExtendedHRE<IExodiaContractsRegistry>;
const { deployments, get, getNetwork } = xhre;

const MINIMUM_UPDATE_INTERVAL = 60 * 5; // 5 mins
const WSSCR = "0xA7727db8DB5afcA6d88eb7FB9E8e322dc043325a";
const WSSCR_DAI_POOL = "0x43d668c6F709C9D7f05C9404707A10d968B0348c";

describe("PriceProvider", function () {
    let addressRegistry: IExternalContractsRegistry;
    let owner: SignerWithAddress, user: SignerWithAddress, architect: SignerWithAddress;
    let balancerOracle: BalancerV2PriceOracle,
        chainlinkOracle: ChainlinkPriceOracle,
        priceProvider: PriceProvider;
    let roles: ExodiaRoles;

    before(async function () {
        [owner, user, architect] = await xhre.ethers.getSigners();
        addressRegistry = externalAddressRegistry.forNetwork(await getNetwork());
    });

    beforeEach(async function () {
        await deployments.fixture([
            EXODIA_ROLES_DID,
            PRICE_PROVIDER_DID,
            BALANCER_V2_PRICE_ORACLE_DID,
        ]);
        const oracleDeployment = await get<ChainlinkPriceOracle__factory>(
            "BalancerV2PriceOracle"
        );
        balancerOracle = await oracleDeployment.contract;
        const priceProviderDeployment = await get<PriceProvider__factory>(
            "PriceProvider"
        );
        priceProvider = await priceProviderDeployment.contract;
        const rolesDeployment = await get<ExodiaRoles__factory>("ExodiaRoles");
        roles = await rolesDeployment.contract;

        await roles.addArchitect(architect.address);

        const ChainlinkPriceOracle = await xhre.ethers.getContractFactory(
            "ChainlinkPriceOracle"
        );
        chainlinkOracle = <ChainlinkPriceOracle>await ChainlinkPriceOracle.deploy();
        await chainlinkOracle.initialize(roles.address, addressRegistry.FTM_USD_FEED);

        // chainlink: DAI/FTM
        await chainlinkOracle
            .connect(architect)
            .setPriceFeed(addressRegistry.DAI, addressRegistry.DAI_USD_FEED);

        await balancerOracle.initialize(
            roles.address,
            addressRegistry.BEETHOVEN_VAULT,
            MINIMUM_UPDATE_INTERVAL
        );
        // balancer: BEETS/FTM
        await balancerOracle
            .connect(architect)
            .setTokenOracle(
                addressRegistry.BEETS,
                addressRegistry.FIDELIO_DUETTO,
                ZERO_ADDRESS
            );
        // balancer: WSSCR/FTM
        await balancerOracle
            .connect(architect)
            .setTokenOracle(WSSCR, WSSCR_DAI_POOL, chainlinkOracle.address);
    });

    it("Can't initialize with zero addresses", async function () {
        await expect(priceProvider.initialize(ZERO_ADDRESS)).to.revertedWith(
            "roles cannot be null address"
        );
    });

    it("Should be able to initialize", async function () {
        await priceProvider.initialize(roles.address);
    });

    it("Can't initialize twice", async function () {
        await priceProvider.initialize(roles.address);

        await expect(priceProvider.initialize(ZERO_ADDRESS)).to.revertedWith(
            "Initializable: contract is already initialized"
        );
    });

    describe("After initialization", function () {
        beforeEach(async function () {
            await priceProvider.initialize(roles.address);
        });

        it("Only architect can set token oracle settings", async function () {
            await expect(
                priceProvider
                    .connect(user)
                    .setTokenOracle(addressRegistry.BEETS, balancerOracle.address)
            ).to.revertedWith("caller is not an architect");
        });

        describe("After token oracle setting: BEETS-FTM", function () {
            beforeEach(async function () {
                await priceProvider
                    .connect(architect)
                    .setTokenOracle(addressRegistry.BEETS, balancerOracle.address);
            });

            it("Should be able to get current price", async function () {
                expect(
                    await priceProvider.getCurrentPrice(addressRegistry.BEETS)
                ).to.equal(await balancerOracle.getCurrentPrice(addressRegistry.BEETS));
            });

            it("Should be able to get safe price", async function () {
                expect(await priceProvider.getSafePrice(addressRegistry.BEETS)).to.equal(
                    await balancerOracle.getSafePrice(addressRegistry.BEETS)
                );
            });

            it("Should be able to update safe price", async function () {
                await priceProvider.updateSafePrice(addressRegistry.BEETS);
            });
        });

        describe("After token oracle setting: wsSCR-FTM", function () {
            beforeEach(async function () {
                await priceProvider
                    .connect(architect)
                    .setTokenOracle(WSSCR, balancerOracle.address);
            });

            it("Should be able to get current price", async function () {
                expect(await priceProvider.getCurrentPrice(WSSCR)).to.equal(
                    await balancerOracle.getCurrentPrice(WSSCR)
                );
            });

            it("Should be able to get safe price", async function () {
                expect(await priceProvider.getSafePrice(WSSCR)).to.equal(
                    await balancerOracle.getSafePrice(WSSCR)
                );
            });

            it("Should be able to update safe price", async function () {
                await priceProvider.updateSafePrice(WSSCR);
            });
        });

        describe("After token oracle setting: DAI-FTM", function () {
            beforeEach(async function () {
                await priceProvider
                    .connect(architect)
                    .setTokenOracle(addressRegistry.DAI, chainlinkOracle.address);
            });

            it("Should be able to get current price", async function () {
                expect(await priceProvider.getCurrentPrice(addressRegistry.DAI)).to.equal(
                    await chainlinkOracle.getCurrentPrice(addressRegistry.DAI)
                );
            });

            it("Should be able to get safe price", async function () {
                expect(await priceProvider.getSafePrice(addressRegistry.DAI)).to.equal(
                    await chainlinkOracle.getSafePrice(addressRegistry.DAI)
                );
            });

            it("Should be able to update safe price", async function () {
                await priceProvider.updateSafePrice(addressRegistry.DAI);
            });
        });
    });
});
