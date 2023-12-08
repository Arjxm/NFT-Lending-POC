import {ethers, run} from 'hardhat';

async function main() {

    const gelatoAutomate = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";
    const fundOwner = "0x5b39E0Ec58De9785DeAb32c178948ad052CFd830"


    const NFTLending = await ethers.getContractFactory('Lending');
    // @ts-ignore
    const nftLending = await NFTLending.deploy(gelatoAutomate,fundOwner);

  await nftLending.deployed();

  await run("verify:verify", {
      address: nftLending.address,
      constructorArguments: [gelatoAutomate,fundOwner],
  })

  console.log('verified and contract deployed to:', nftLending.address);

    // Call the AddFundToContract function
    const addFundsTransaction = await nftLending.AddFundToContract({ value: ethers.utils.parseEther("500") });
    await addFundsTransaction.wait();
  
    console.log('Funds added to the contract');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
