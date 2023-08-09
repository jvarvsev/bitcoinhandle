// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract BitcoinHandle is Ownable, ERC721Enumerable {
    using Strings for uint256;

    // Constants
    string public subhandles;
    uint256 public constant ONE_YEAR_IN_SECONDS = 365 days;
    uint256 public tokenIdCounter = 1;
    uint256 public constant MAX_CHARACTER_LENGTH = 30;
    uint256 public constant MINIMUM_CHARACTER_COUNT = 1;
    uint256 public constant MAXIMUM_XN_CHARACTERS = 8;
    bytes public constant HANDLE_SUFFIX = hex"e282bf"; // ".₿" in UTF-8 encoding
    uint256 private _totalSupply;
    address private deployerAddress;
    uint256 private contractDeployedTimestamp;

    // Structs
    struct Handle {
        uint256 nftId;
        address owner;
        uint256 expirationTimestamp;
        address parentOwner;
        uint256 subhandleCount;
        uint256 parentCharacterCount;
        uint256 subhandleCharacterCount;
        mapping(string => Subhandle) subhandles;
        uint256 registrationYears;
    }

    struct HandleInfo {
        address owner;
        uint256 expirationTimestamp;
        address parentOwner;
        uint256 subhandleCount;
    }

    struct Subhandle {
        uint256 nftId;
        address owner;
        uint256 expirationTimestamp;
        bool requested;
        uint256 registrationYears;
    }

    struct RenewedSubhandle {
        string subhandleName;
        string parentHandleName;
        address parentOwner;
        uint256 newExpirationTimestamp;
    }

    struct ParentHandle {
        address parentOwner;
        bool permissionEnabled;
    }

    // Declare the ParentOwnerUpdated event
    event ParentOwnerUpdated(string handleWithSuffix, address indexed oldParentOwner, address indexed newParentOwner);


    // Mappings
    mapping(string => Handle) private handles;
    mapping(uint256 => string) private handleNames;
    mapping(uint256 => string) private handleTokenURIs;
    mapping(address => mapping(string => ParentHandle)) public parentHandleOwners;
    mapping(string => uint256) private tokenIds;
    mapping(string => address) private handleTotRBTCAddress;
    mapping(string => address) private handleTotBTCAddress;
    mapping(address => uint256) public parentHandleBalances;
    mapping(string => Subhandle) private subhandleMappings;
    mapping(string => uint256) private subhandleExpirationTimestamps;
    mapping(string => bool) private toggledSubhandlePermissions;
    mapping(uint256 => uint256) private parentTokenIds;

    // Events
    event HandleRegistered(
        address indexed owner,
        string handleName,
        uint256 expirationTimestamp
    );

    event HandleRenewed(
        address indexed owner,
        string handleName,
        uint256 newExpirationTimestamp
    );

    event SubhandleRegistered(
        address indexed owner,
        string subhandleName,
        string parentHandleName,
        address parentOwner,
        uint256 expirationTimestamp
    );

    event SubhandleRenewed(
        address indexed owner,
        string subhandleName,
        string parentHandleName,
        address indexed parentOwner,
        uint256 newExpirationTimestamp
    );

    event SubhandleRequest(
        address indexed requester, 
        string subhandleName, 
        string parentHandleName
    );

    event HandlePermissionToggled(
        address indexed owner,
        string parentHandleName,
        bool permissionEnabled
    );

    event HandleTransferred(
        address indexed previousOwner,
        string handleName,
        address indexed newOwner
    );

    event SubhandleTransferred(
        address indexed previousOwner,
        string handleName,
        address indexed newOwner
    );

    uint256[] public handleFees;
    uint256[] public subhandleFees;
    
    constructor() ERC721("BitcoinHandle", "SSI") {
        // Initialize handle fees
        handleFees.push(0); // Placeholder for 0 index
        handleFees.push(0.03 ether); // 1 Character
        handleFees.push(0.02 ether); // 2 Characters
        handleFees.push(0.01 ether); // 3 Characters
        handleFees.push(0.0003 ether); // 4 Characters
        handleFees.push(0.0002 ether); // 5 Characters
        handleFees.push(0.0001 ether); // 6+ Characters

        // Initialize subhandle fees
        subhandleFees.push(0); // Placeholder for 0 index
        subhandleFees.push(0.015 ether); // 1 Character
        subhandleFees.push(0.01 ether); // 2 Characters
        subhandleFees.push(0.005 ether); // 3 Characters
        subhandleFees.push(0.00015 ether); // 4 Characters
        subhandleFees.push(0.0001 ether); // 5 Characters
        subhandleFees.push(0.00005 ether); // 6+ Characters

        deployerAddress = msg.sender; // Store the deployer's address in the state variable
    }

    // Function to calculate handle fee using handleFees array
    function calculateHandleFee(string memory handleName, uint256 registrationYears) public view returns (uint256) {
        require(handleFees.length >= 7, "Invalid handleFees array");

        uint256 characterCount = bytes(handleName).length;
        uint256 fee;

        if (characterCount >= 6) {
            fee = handleFees[6];
        } else {
            fee = handleFees[characterCount];
        }

        // Multiply the fee by the number of registration years
        fee = fee * registrationYears;

        return fee;
    }

    // Function to calculate subhandle fee using subhandleFees array
    function calculateSubhandleFee(string memory subhandleName, uint256 registrationYears) public view returns (uint256) {
        require(subhandleFees.length >= 7, "Invalid subhandleFees array");

        uint256 characterCount = bytes(subhandleName).length;
        uint256 fee;

        if (characterCount >= 6) {
            fee = subhandleFees[6];
        } else {
            fee = subhandleFees[characterCount];
        }

        // Multiply the fee by the number of registration years
        fee = fee * registrationYears;

        return fee;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function setHandleTokenURI(uint256 tokenId, string memory tokenURI) internal {
        require(_exists(tokenId), "Token does not exist");
        handleTokenURIs[tokenId] = tokenURI;
    }

    modifier validHandleName(string memory handleName) {
        require(
            bytes(handleName).length >= MINIMUM_CHARACTER_COUNT &&
            bytes(handleName).length <= MAX_CHARACTER_LENGTH &&
            !hasSuffix(handleName) &&
            !hasZWJ(handleName) &&
            !hasUppercase(handleName) &&
            (!isXNPrefix(handleName) || bytes(handleName).length <= MAXIMUM_XN_CHARACTERS) &&
            countDots(handleName) <= 1, // Add this condition to allow only one dot
            "Invalid handle name"
        );
        _;
    }

    function countDots(string memory handleName) internal pure returns (uint256) {
        bytes memory handleBytes = bytes(handleName);
        uint256 dotCount = 0;
        for (uint256 i = 0; i < handleBytes.length; i++) {
            if (handleBytes[i] == bytes1('.')) { // Compare with a byte literal using bytes1()
                dotCount++;
            }
        }
        return dotCount;
    }

    function hasSuffix(string memory handleName) internal pure returns (bool) {
        bytes memory handleBytes = bytes(handleName);
        bytes memory suffixBytes = HANDLE_SUFFIX;

        if (handleBytes.length < suffixBytes.length) {
            return false;
        }

        for (uint256 i = 0; i < suffixBytes.length; i++) {
            if (handleBytes[handleBytes.length - suffixBytes.length + i] != suffixBytes[i]) {
                return false;
            }
        }

        return true;
    }

    function hasZWJ(string memory handleName) internal pure returns (bool) {
        bytes memory handleBytes = bytes(handleName);
        bytes memory zwjBytes = hex"e2808d"; // UTF-8 encoding of ZWJ

        if (handleBytes.length < zwjBytes.length) {
            return false;
        }

        for (uint256 i = 0; i < handleBytes.length - zwjBytes.length + 1; i++) {
            bool foundZWJ = true;
            for (uint256 j = 0; j < zwjBytes.length; j++) {
                if (handleBytes[i + j] != zwjBytes[j]) {
                    foundZWJ = false;
                    break;
                }
            }
            if (foundZWJ) {
                return true;
            }
        }

        return false;
    }

    function hasUppercase(string memory handleName) internal pure returns (bool) {
        bytes memory handleBytes = bytes(handleName);
        for (uint256 i = 0; i < handleBytes.length; i++) {
            if (isUppercase(handleBytes[i])) {
                return true;
            }
        }
        return false;
    }

    function isUppercase(bytes1 character) internal pure returns (bool) {
        uint8 asciiValue = uint8(character);
        return (asciiValue >= 65 && asciiValue <= 90);
    }

    function isXNPrefix(string memory handleName) internal pure returns (bool) {
        bytes memory handleBytes = bytes(handleName);
        bytes memory xnPrefixBytes = bytes("xn--");

        if (handleBytes.length < xnPrefixBytes.length) {
            return false;
        }

        for (uint256 i = 0; i < xnPrefixBytes.length; i++) {
            if (handleBytes[i] != xnPrefixBytes[i]) {
                return false;
            }
        }

        return true;
    }

    modifier noDot(string memory _handle) {
        require(!containsSpecialCharacters(_handle, "."), "Handle cannot contain '.'");
        _;
    }

     // Function to check if a string contains a specific special character
    function containsSpecialCharacters(string memory _str, string memory _specialCharacter) internal pure returns (bool) {
        bytes memory strBytes = bytes(_str);
        bytes memory charBytes = bytes(_specialCharacter);

        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == charBytes[0]) {
                return true;
            }
        }
        return false;
    }

    modifier validMainPart(string memory handleName) {
        bytes memory handleBytes = bytes(handleName);

        // Regular expression pattern to match only alphanumeric characters, hyphens, and dot (.)
        bytes memory allowedPattern = abi.encodePacked("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-."); 

        require(handleBytes.length > 0 && handleBytes.length <= MAX_CHARACTER_LENGTH, "Invalid handle length");
        for (uint256 i = 0; i < handleBytes.length; i++) {
            bytes1 character = handleBytes[i];
            bool isAllowedCharacter = false;
            for (uint256 j = 0; j < allowedPattern.length; j++) {
                if (character == allowedPattern[j]) {
                    isAllowedCharacter = true;
                    break;
                }
            }
            require(isAllowedCharacter, "Invalid character in handle name");
        }

        // Check if the handle starts or ends with a hyphen or dot
        require(handleBytes[0] != '-' && handleBytes[0] != '.' && handleBytes[handleBytes.length - 1] != '-' && handleBytes[handleBytes.length - 1] != '.', "Handle cannot start or end with a hyphen or dot");

        // Check if the handle contains two consecutive hyphens or dots
        for (uint256 i = 0; i < handleBytes.length - 1; i++) {
            require(!(handleBytes[i] == '-' && handleBytes[i + 1] == '-') && !(handleBytes[i] == '.' && handleBytes[i + 1] == '.'), "Handle cannot contain consecutive hyphens or dots");
        }

        _;
    }

    function subhandlePart(string memory handleName) internal pure returns (string memory) {
        bytes memory handleBytes = bytes(handleName);
        uint256 lastDotIndex = findLastDot(handleBytes);

        return substring(handleName, 0, lastDotIndex);
    }

    function parentPart(string memory handleName) internal pure returns (string memory) {
        bytes memory handleBytes = bytes(handleName);
        uint256 lastDotIndex = findLastDot(handleBytes);

        return substring(handleName, lastDotIndex + 1, handleBytes.length - lastDotIndex - 1);
    }

    function substring(string memory str, uint256 startIndex, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(startIndex + length <= strBytes.length, "Invalid substring length");

        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[startIndex + i];
        }

        return string(result);
    }

    function findLastDot(bytes memory handleBytes) internal pure returns (uint256) {
        for (uint256 i = handleBytes.length - 1; i >= 0; i--) {
            if (handleBytes[i] == '.') {
                return i;
            }
        }
        return 0;
    }

    function stringToAddress(string memory _str) internal pure returns (address) {
        bytes memory data = bytes(_str);
        uint256 result = 0;
        for (uint256 i = 0; i < data.length; i++) {
            uint256 val = uint256(uint8(data[i]));
            if (val >= 48 && val <= 57) {
                result = result * 16 + (val - 48);
            } else if (val >= 65 && val <= 70) {
                result = result * 16 + (val - 55);
            } else if (val >= 97 && val <= 102) {
                result = result * 16 + (val - 87);
            } else {
                revert("Invalid address string");
            }
        }
        return address(uint160(result));
    }

    modifier onlyHandleOwner(string memory handleName) {
        string memory handleWithSuffix = string(abi.encodePacked(handleName, ".", string(HANDLE_SUFFIX)));
        require(ownerOf(tokenIds[handleWithSuffix]) == msg.sender, "You are not the owner of the handle");
        _;
    }

    function toggleSubhandlePermission(string memory parentHandleName) external {
        require(bytes(parentHandleName).length > 0, "Invalid parent handle name");

        string memory parentHandleWithSuffix = string(abi.encodePacked(parentHandleName, ".", string(HANDLE_SUFFIX)));

        Handle storage parentHandle = handles[parentHandleWithSuffix];
        require(parentHandle.nftId != 0, "Parent handle not registered");
        require(msg.sender == parentHandle.parentOwner, "Only the parent handle owner can toggle permission");

        ParentHandle storage parentPermissions = parentHandleOwners[msg.sender][parentHandleWithSuffix];
        parentPermissions.permissionEnabled = !parentPermissions.permissionEnabled;

        // Emit the event with the parent handle name including the suffix
        emit HandlePermissionToggled(
            msg.sender, // Owner address
            parentHandleWithSuffix, // Parent handle name including the suffix
            parentPermissions.permissionEnabled // Permission enabled flag
        );
    }

    function isPermissionEnabled(string memory parentHandleName, address parentOwner) public view returns (bool) {
        ParentHandle storage parentPermissions = parentHandleOwners[parentOwner][parentHandleName];
        return parentPermissions.permissionEnabled;
    }

    function requestSubhandle(string memory subhandleAndParent) external {
        string memory subhandleName = subhandlePart(subhandleAndParent);
        string memory parentHandleWithSuffix = string(abi.encodePacked(parentPart(subhandleAndParent), ".", string(HANDLE_SUFFIX)));

        require(bytes(subhandleName).length > 0 && bytes(parentHandleWithSuffix).length > 0, "Invalid subhandle and parent handle");

        require(
            !isPermissionEnabled(parentHandleWithSuffix, handles[parentHandleWithSuffix].parentOwner) || msg.sender == handles[parentHandleWithSuffix].parentOwner,
            "Permission not granted"
        );

        Handle storage parentHandle = handles[parentHandleWithSuffix];
        Subhandle storage subhandle = parentHandle.subhandles[subhandleName];

        require(subhandle.owner == address(0), "Subhandle already registered");
        require(!subhandle.requested, "Subhandle request is pending");

        subhandle.requested = true;

        emit SubhandleRequest(msg.sender, subhandleName, parentPart(subhandleAndParent));
    }

    function approveSubhandleRequest(
        string memory subhandleName,
        string memory parentHandleName,
        address requester,
        uint256 registrationYears
    ) external onlyHandleOwner(parentHandleName) {
        string memory parentHandleWithSuffix = string(abi.encodePacked(parentHandleName, ".", string(HANDLE_SUFFIX)));

        Subhandle storage subhandle = handles[parentHandleWithSuffix].subhandles[subhandleName];
        require(subhandle.requested, "No pending request for this subhandle");
        require(subhandle.owner == address(0), "Subhandle already registered");

        subhandle.requested = false;

        uint256 tokenId = _totalSupply + 1;
        _totalSupply += 1;
        _mint(requester, tokenId);

        setHandleTokenURI(tokenId, handleTokenURIs[tokenIds[parentHandleWithSuffix]]);

        subhandle.nftId = tokenId;
        subhandle.owner = requester;
        subhandle.expirationTimestamp = block.timestamp + (ONE_YEAR_IN_SECONDS * registrationYears);
        subhandle.registrationYears = registrationYears;

        handleNames[tokenId] = string(abi.encodePacked(subhandleName, ".", parentHandleName, ".", string(HANDLE_SUFFIX)));
        tokenIds[handleNames[tokenId]] = tokenId;

        emit SubhandleRegistered(
            requester,
            subhandleName,
            parentHandleName,
            handles[parentHandleWithSuffix].parentOwner,
            subhandle.expirationTimestamp
        );
    }

    function mintHandle(
        string memory handleName,
        string memory tokenURI,
        uint256 registrationYears
    ) external payable noDot(handleName) validMainPart(handleName) validHandleName(handleName) {
        // Check if the handle with suffix is already registered
        string memory handleWithSuffix = string(abi.encodePacked(handleName, ".", string(HANDLE_SUFFIX)));
        require(handles[handleWithSuffix].nftId == 0, "Handle already registered");

        uint256 registrationFee = calculateHandleFee(handleName, registrationYears);
        require(msg.value >= registrationFee, "Insufficient registration fee");

        uint256 tokenId = _totalSupply + 1;
        _totalSupply += 1;
        _mint(msg.sender, tokenId);
        setHandleTokenURI(tokenId, tokenURI);

        Handle storage newHandle = handles[handleWithSuffix];
        newHandle.nftId = tokenId;
        newHandle.expirationTimestamp = block.timestamp + (ONE_YEAR_IN_SECONDS * registrationYears);
        newHandle.parentOwner = msg.sender;
        newHandle.registrationYears = registrationYears;

        handleNames[tokenId] = handleWithSuffix;
        tokenIds[handleWithSuffix] = tokenId;

        // Transfer the registration fee directly to the deployer's address
        address payable deployer = payable(deployerAddress);
        deployer.transfer(msg.value);

        emit HandleRegistered(
            msg.sender,
            handleWithSuffix,
            newHandle.expirationTimestamp
        );
    }

    function renewHandle(string memory handleName, uint256 renewalYears) external payable {
        string memory handleWithSuffix = string(abi.encodePacked(handleName, ".", string(HANDLE_SUFFIX)));
        require(handles[handleWithSuffix].nftId != 0, "Handle not registered");

        uint256 renewalFee = calculateHandleFee(handleName, renewalYears);
        require(msg.value >= renewalFee * renewalYears, "Insufficient renewal fee");

        Handle storage handle = handles[handleWithSuffix];

        handle.expirationTimestamp += ONE_YEAR_IN_SECONDS * renewalYears;

        // Transfer the renewal fee to the deployer's address
        address payable deployer = payable(deployerAddress);
        deployer.transfer(msg.value);

        emit HandleRenewed(
            handle.owner,
            handleWithSuffix,
            handle.expirationTimestamp
        );
    }

    function mintSubhandle(
        string memory subhandleAndParent,
        string memory tokenURI,
        uint256 registrationYears
    ) external payable validMainPart(subhandleAndParent) validHandleName(subhandleAndParent) {
        string memory subhandleName = subhandlePart(subhandleAndParent);
        string memory parentHandleWithSuffix = string(abi.encodePacked(parentPart(subhandleAndParent), ".", string(HANDLE_SUFFIX)));

        require(bytes(subhandleName).length > 0 && bytes(parentHandleWithSuffix).length > 0, "Invalid subhandle and parent handle");

        if (msg.sender != handles[parentHandleWithSuffix].parentOwner) {
            uint256 registrationFee = calculateSubhandleFee(subhandleName, registrationYears);
            require(msg.value >= registrationFee, "Insufficient registration fee");

            address payable parentOwner = payable(handles[parentHandleWithSuffix].parentOwner);
            parentOwner.transfer(msg.value);
        }

        require(!handles[parentHandleWithSuffix].subhandles[subhandleName].requested, "Subhandle request is pending");
        require(
            isPermissionEnabled(parentHandleWithSuffix, handles[parentHandleWithSuffix].parentOwner) || msg.sender == handles[parentHandleWithSuffix].parentOwner,
            "Permission not granted"
        );

        // Ensure the subhandle does not already exist
        require(handles[parentHandleWithSuffix].subhandles[subhandleName].nftId == 0, "Subhandle already registered");

        uint256 tokenId = _totalSupply + 1;
        _totalSupply += 1;
        _mint(msg.sender, tokenId);
        setHandleTokenURI(tokenId, tokenURI);

        Handle storage parentHandle = handles[parentHandleWithSuffix];
        Subhandle storage subhandle = parentHandle.subhandles[subhandleName];

        subhandle.nftId = tokenId;
        subhandle.owner = msg.sender;
        subhandle.requested = false;
        subhandle.expirationTimestamp = block.timestamp + (ONE_YEAR_IN_SECONDS * registrationYears);
        subhandle.registrationYears = registrationYears;

        parentHandle.subhandleCount += 1;

        string memory subhandleWithSuffix = string(abi.encodePacked(subhandleName, ".", parentHandleWithSuffix));
        handleNames[tokenId] = subhandleWithSuffix;
        tokenIds[subhandleWithSuffix] = tokenId;

        // Calculate the Expiration Timestamp using the expiration block
        uint256 expirationTimestamp = subhandle.expirationTimestamp;

        // Emit the SubhandleMinted event with the required values
        emit SubhandleRegistered(
            msg.sender, // Use msg.sender as the owner of the new subhandle
            subhandleWithSuffix, // Use subhandleWithSuffix instead of subhandleName
            parentHandleWithSuffix,
            handles[parentHandleWithSuffix].parentOwner,
            expirationTimestamp
        );

    }

    function renewSubhandle(string memory subhandleAndParent, uint256 renewalYears) external payable {
        string memory subhandleName = subhandlePart(subhandleAndParent);
        string memory parentHandleWithSuffix = string(abi.encodePacked(parentPart(subhandleAndParent), ".", string(HANDLE_SUFFIX)));

        require(bytes(subhandleName).length > 0 && bytes(parentHandleWithSuffix).length > 0, "Invalid subhandle and parent handle");
        require(handles[parentHandleWithSuffix].nftId != 0, "Parent handle not registered");

        Subhandle storage subhandle = handles[parentHandleWithSuffix].subhandles[subhandleName];
        require(subhandle.nftId != 0, "Subhandle not registered");

        uint256 renewalFee = calculateSubhandleFee(subhandleName, renewalYears);

        // Check if the caller is the owner of the parent handle
        if (msg.sender != handles[parentHandleWithSuffix].parentOwner) {
            require(msg.value >= renewalFee * renewalYears, "Insufficient renewal fee");
        }

        // Transfer the renewal fee to the parent handle owner
        address payable parentOwner = payable(handles[parentHandleWithSuffix].parentOwner);
        parentOwner.transfer(msg.value);

        subhandle.expirationTimestamp += ONE_YEAR_IN_SECONDS * renewalYears;

        // Construct the subhandle and parent handle names with suffix
        string memory subhandleWithSuffix = string(abi.encodePacked(subhandleName, ".", parentHandleWithSuffix));
        handleNames[subhandle.nftId] = subhandleWithSuffix; // Use subhandleWithSuffix instead of subhandleAndParent
        tokenIds[subhandleWithSuffix] = subhandle.nftId; // Use subhandleWithSuffix instead of subhandleAndParent

        // Create the RenewedSubhandle struct
        RenewedSubhandle memory renewedSubhandle = RenewedSubhandle(
            subhandleWithSuffix, // Use subhandleWithSuffix instead of subhandleAndParent
            parentHandleWithSuffix,
            handles[parentHandleWithSuffix].parentOwner,
            subhandle.expirationTimestamp
        );

        // Emit the SubhandleRenewed event with individual arguments from the RenewedSubhandle struct
        emit SubhandleRenewed(
            msg.sender, // Use msg.sender as the owner of the renewed subhandle
            renewedSubhandle.subhandleName,
            renewedSubhandle.parentHandleName,
            renewedSubhandle.parentOwner,
            renewedSubhandle.newExpirationTimestamp
        );
    }

    function getHandleInfo(string memory handleName) external view returns (HandleInfo memory) {
        string memory handleWithSuffix = string(abi.encodePacked(handleName, ".", string(HANDLE_SUFFIX)));
        Handle storage handle = handles[handleWithSuffix];
         return HandleInfo(
         handle.owner,
         handle.expirationTimestamp,
         handle.parentOwner,
         handle.subhandleCount
         );
    }

    function getSubhandleInfo(string memory subhandleName, string memory parentHandleName)
        external
        view
        returns (Subhandle memory)
    {
        string memory parentHandleWithSuffix = string(abi.encodePacked(parentHandleName, ".", string(HANDLE_SUFFIX)));
        return handles[parentHandleWithSuffix].subhandles[subhandleName];
    }

    function getHandleTokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return handleTokenURIs[tokenId];
    }

    function getHandleName(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return handleNames[tokenId];
    }

    function getHandleExpirationTimestamp(string memory handleName) external view returns (uint256) {
        string memory handleWithSuffix = string(abi.encodePacked(handleName, ".", string(HANDLE_SUFFIX)));
        return handles[handleWithSuffix].expirationTimestamp;
    }

    function getSubhandleExpirationTimestamp(string memory subhandleName, string memory parentHandleName)
        external
        view
        returns (uint256)
    {
        string memory parentHandleWithSuffix = string(abi.encodePacked(parentHandleName, ".", string(HANDLE_SUFFIX)));
        return handles[parentHandleWithSuffix].subhandles[subhandleName].expirationTimestamp;
    }

    function getTimestampFromDate(uint16 year, uint8 month, uint8 day) internal pure returns (uint256) {
        require(year >= 1970 && year <= 2106, "Invalid year");
        require(month >= 1 && month <= 12, "Invalid month");
        require(day >= 1 && day <= 31, "Invalid day");

        uint256 hourInSeconds = 3600;
        uint256 dayInSeconds = 86400;
        uint256 yearInSeconds = 31536000;

        uint16 i;

        // Year
        uint256 timestamp = (year - 1970) * yearInSeconds;

        // Month
        uint8[12] memory monthDays = [
            31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
        ];
        for (i = 1; i < month; i++) {
            timestamp += uint256(monthDays[i - 1]) * dayInSeconds;
        }

        // Day
        timestamp += uint256(day - 1) * dayInSeconds;

        // Leap years
        uint256 leapYears = (year - 1968) / 4 - (year - 1900) / 100 + (year - 1600) / 400;
        timestamp += leapYears * dayInSeconds;

        // Adjust for leap year
        if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) && month > 2) {
            timestamp += dayInSeconds;
        }

        // Hours (assuming 00:00:00 UTC)
        timestamp += 20 * hourInSeconds;

        return timestamp;
    }

    function getHumanReadableDateTime(uint256 timestamp) external pure returns (string memory) {
        uint256 unixTimestamp = timestamp;
        uint8[12] memory monthDays = [
            31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
        ];
        uint256 year;
        uint256 month;
        uint256 day;
        uint256 hour;
        uint256 minute;
        uint256 second;

        uint256 time = unixTimestamp;
        uint256 secondsInDay = 86400;
        uint256 secondsInHour = 3600;
        uint256 secondsInMinute = 60;
        // Year
        while (time >= secondsInDay * 365) {
            if ((year + 1) % 4 == 0) {
                if ((year + 1) % 100 == 0 && (year + 1) % 400 != 0) {
                    time -= secondsInDay * 365;
                } else {
                    time -= secondsInDay * 366;
                    year += 1;
                }
            } else {
                time -= secondsInDay * 365;
                year += 1;
            }
        }

        // Month
        bool leapYear = (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
        for (month = 0; month < 12; month++) {
            uint256 daysInMonth = monthDays[month];
            if (leapYear && month == 1) {
                daysInMonth = 29;
            }
            if (time >= secondsInDay * daysInMonth) {
                time -= secondsInDay * daysInMonth;
            } else {
                break;
            }
        }

        // Day
        day = time / secondsInDay;
        time -= day * secondsInDay;

        // Hour
        hour = time / secondsInHour;
        time -= hour * secondsInHour;

        // Minute
        minute = time / secondsInMinute;
        time -= minute * secondsInMinute;

        // Second
        second = time;

        return string(abi.encodePacked(
            uint2str(year),
            "-",
            uint2str(month + 1),
            "-",
            uint2str(day + 1),
            " ",
            uint2str(hour),
            ":",
            uint2str(minute),
            ":",
            uint2str(second)
        ));
    }

    function uint2str(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
         return string(buffer);
    }

    modifier updateParentOwner(string memory handleWithSuffix, address newParentOwner) {
        Handle storage handle = handles[handleWithSuffix];
        require(handle.nftId != 0, "Handle not registered");
        address currentParentOwner = handle.parentOwner;
        require(currentParentOwner != newParentOwner, "New owner is the same as the current owner");

        handle.parentOwner = newParentOwner;
        emit ParentOwnerUpdated(handleWithSuffix, currentParentOwner, newParentOwner);
        _;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override updateParentOwner(handleNames[tokenId], to) {
        // Get the parent token ID
        uint256 parentTokenId = parentTokenIds[tokenId];

        // Call the safe transfer function from ERC721 contract
        super.safeTransferFrom(from, to, tokenId, _data);

        // Emit events after the transfer
        if (parentTokenId != 0) {
            emit SubhandleTransferred(
                from,
                handleNames[tokenId],
                to
            );

            emit HandleTransferred(
                from,
                handleNames[parentTokenId],
                to
            );
        } else {
            emit HandleTransferred(
                from,
                handleNames[tokenId],
                to
            );
        }
    }



}