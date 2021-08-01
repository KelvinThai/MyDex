pragma solidity 0.8.0;
// just import the Zrx interface from openzeppelin library and it's done
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Zrx is ERC20 {
  constructor() ERC20('ZRX', 'Zrx token') {}
// this function is for testing, allow to give free token
  function faucet(address to, uint amount) external {
    _mint(to, amount);
  }
}
