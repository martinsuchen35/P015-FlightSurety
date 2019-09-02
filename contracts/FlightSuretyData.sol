pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    struct Airline {
        bool registered;
        bool funded;
    }

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 takeOff;
        uint256 landing;
        address airline;
        string flightRef;
        uint price;
        string from;
        string to;
        mapping(address => bool) bookings;
        mapping(address => uint) insurances;
    }

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    address public firstAirline;
    address[] internal passengers;

    mapping(address => bool) public authorizedCallers; // Addresses allowed to call this contract
    mapping(address => Airline) public airlines;
    mapping(bytes32 => Flight) public flights;
    mapping(address => uint) public withdrawals;

    uint public registeredAirlinesCount;
    bytes32[] public flightKeys;
    uint public indexFlightKeys = 0;

    event Paid(address recipient, uint amount);
    event Funded(address airline);
    event AirlineRegistered(address origin, address newAirline);
    event Credited(address passenger, uint amount);

    constructor(address _firstAirline)
    public {
        contractOwner = msg.sender;
        firstAirline = _firstAirline;
        registeredAirlinesCount = 1;
        airlines[firstAirline].registered = true;
    }

    /**
     *  Modifiers help avoid duplication of code. They are typically used to validate something
     *  before a function is allowed to be executed.
     */

    //  Modifier that requires the "operational" boolean variable to be "true"
    //      This is used on all state changing functions to pause the contract in
    //      the event there is an issue that needs to be fixed
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    // Modifier that requires the "ContractOwner" account to be the function caller
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    // Modifier that requires caller to be previously authorized address
    modifier requireCallerAuthorized() {
        require(authorizedCallers[msg.sender] == true, "Caller is not authorized to call this function");
        _;
    }

    // TODO: add comments and rename
    modifier differentModeRequest(bool status) {
        require(status != operational, "Contract already in the state requested");
        _;
    }

    modifier requireFlightRegistered(bytes32 flightKey) {
        require(flights[flightKey].isRegistered, "This flight does not exist");
        _;
    }

    // TODO: add comments and rename
    modifier valWithinRange(uint val, uint low, uint up) {
        require(val < up, "Value higher than max allowed");
        require(val > low, "Value lower than min allowed");
        _;
    }

    // TODO: add comments and rename
    modifier notYetProcessed(bytes32 flightKey) {
        require(flights[flightKey].statusCode == 0, "This flight has already been processed");
        _;
    }

    /**
     *  Utility Functions
     */
    function isOperational() public view returns(bool) {
        return operational;
    }

    // Sets contract operations on/off
    // When operational mode is disabled, all write transactions except for this one will fail
    function setOperatingStatus(bool mode)
    external
    requireContractOwner
    differentModeRequest(mode) {
        operational = mode;
    }

    function authorizeCaller(address callerAddress)
    external
    requireContractOwner
    requireIsOperational {
        authorizedCallers[callerAddress] = true;
    }

    function hasFunded(address airlineAddress)
    external
    view
    returns (bool _hasFunded) {
        _hasFunded = airlines[airlineAddress].funded;
    }

    function isRegistered(address airlineAddress)
    external
    view
    returns (bool _registered) {
        _registered = airlines[airlineAddress].registered;
    }

    function getFlightKey(string flightRef, string destination, uint256 timestamp)
    public
    pure
    returns (bytes32) {
        // TODO
        return keccak256(abi.encodePacked(flightRef, destination, timestamp));
    }

    function paxOnFlight(string flightRef, string destination, uint256 timestamp, address passenger)
    public
    view
    returns (bool onFlight) {
        bytes32 flightKey = getFlightKey(flightRef, destination, timestamp);
        onFlight = flights[flightKey].bookings[passenger];
    }

    function subscribedInsurance(string flightRef, string destination, uint256 timestamp, address passenger)
    public
    view
    returns (uint amount) {
        bytes32 flightKey = getFlightKey(flightRef, destination, timestamp);
        amount = flights[flightKey].insurances[passenger];
    }

    function getFlightPrice(bytes32 flightKey)
    external
    view
    returns (uint price) {
        price = flights[flightKey].price;
    }

    // Add an airline to the registration queue
    // Can only be called from FlightSuretyApp contract
    function registerAirline(address airlineAddress, address originAddress)
    external
    requireIsOperational
    requireCallerAuthorized {
        registeredAirlinesCount++;
        airlines[airlineAddress].registered = true;
        emit AirlineRegistered(originAddress, airlineAddress);
    }

    function registerFlight(uint _takeOff, uint _landing, string _flight, uint _price, string _from, string _to, address originAddress)
    external
    requireIsOperational
    requireCallerAuthorized {
        require(_takeOff > now, "A flight cannot take off in the past");
        require(_landing > _takeOff, "A flight cannot land before taking off");

        Flight memory flight = Flight(true, 0, _takeOff, _landing, originAddress, _flight, _price, _from, _to);
        bytes32 flightKey = keccak256(abi.encodePacked(_flight, _to, _landing));
        flights[flightKey] = flight;
        indexFlightKeys = flightKeys.push(flightKey).sub(1);
    }

    // Buy insurance for a flight
    // TODO: rename to buy
    function book(bytes32 flightKey, uint amount, address originAddress)
    external
    requireIsOperational
    requireCallerAuthorized
    requireFlightRegistered(flightKey)
    payable {
        Flight storage flight = flights[flightKey];
        flight.bookings[originAddress] = true;
        flight.insurances[originAddress] = amount;
        passengers.push(originAddress);
        withdrawals[flight.airline] = flight.price;
    }

    // Credits payouts to insurees
    function creditInsurees(bytes32 flightKey)
    internal
    requireIsOperational
    requireFlightRegistered(flightKey) {
        Flight storage flight = flights[flightKey];
        for (uint i = 0; i < passengers.length; i++) {
            withdrawals[passengers[i]] = flight.insurances[passengers[i]];
            emit Credited(passengers[i], flight.insurances[passengers[i]]);
        }
    }

    // Transfers eligible payout funds to insuree
    function pay(address originAddress)
    external
    requireIsOperational
    requireCallerAuthorized {
        // Check-Effect-Interaction pattern to protect against re-entracy attack
        // 1. Check
        require(withdrawals[originAddress] > 0, "No amount to be transferred to this address");
        // 2. Effect
        uint amount = withdrawals[originAddress];
        withdrawals[originAddress] = 0;
        // 3. Interaction
        originAddress.transfer(amount);
        emit Paid(originAddress, amount);
    }

    // Initial funding for the insurance. Unless there are too many delayed flights
    // resulting in insurance payouts, the contract should be self-sustaining
    function fund(address originAddress)
    public
    requireIsOperational
    requireCallerAuthorized
    payable {
        airlines[originAddress].funded = true;
        emit Funded(originAddress);
    }

    function processFlightStatus(bytes32 flightKey, uint8 statusCode)
    external
    requireFlightRegistered(flightKey)
    requireIsOperational
    requireCallerAuthorized
    notYetProcessed(flightKey) {
        // 1. Check
        Flight storage flight = flights[flightKey];
        // 2. Effect
        flight.statusCode = statusCode;
        // 3. Interact
        // 20 = "flight delay due to airline"
        if (statusCode == 20) {
            creditInsurees(flightKey);
        }
    }

    // Fallback function for funding smart contract.
    function()
    external
    requireCallerAuthorized
    payable {
        require(msg.data.length == 0);
        fund(msg.sender);
    }


}

