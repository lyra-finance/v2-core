import {getSignerContext} from "./utils/env/signerContext";
import {deployPMRM} from "./deploy/deployPMRM";

async function main() {
  const sc = await getSignerContext();
  await deployPMRM(sc);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
