pragma solidity >=0.4.21 <0.6.0;

import "./AccessControl.sol";

contract RPSCore is AccessControl {
    uint constant ROCK = 1000;
    uint constant PAPER = 2000;
    uint constant SCISSOR = 3000;

    uint constant GAME_RESULT_DRAW = 1;
    uint constant GAME_RESULT_HOST_WIN = 2;
    uint constant GAME_RESULT_GUEST_WIN = 3;
    uint constant GAME_RESULT_GUEST_WIN_BY_HOST_CHEAT = 4;

    uint constant GAME_STATE_AVAILABLE_TO_JOIN = 1;
    uint constant GAME_STATE_WAITING_HOST_REVEAL = 2;
    uint constant GAME_STATE_CLOSED = 3;

    uint constant DEVELOPER_TIP_PERCENT = 5;

    uint constant TIME_GAME_EXPIRE = 1 hours;

    address payable constant DUMMY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct Game {
        uint id;
        uint state;
        uint timeExpire;
        uint valueBet;
        uint gestureGuest;
        bytes32 hashGestureHost;
        address payable addressHost;
        address payable addressGuest;
    }

    event LogCloseGameSuccessed(uint _id, uint _valueReturn);
    event LogCreateGameSuccessed(uint _id, uint _valuePlayerHostBid);
    event LogJoinGameSuccessed(uint _id, address _addressHost);
    event LogRevealGameSuccessed(uint _id,
                                    uint _result,
                                    address indexed _addressPlayerWin,
                                    address indexed _addressPlayerLose,
                                    uint _valuePlayerWin,
                                    uint _valuePlayerLose,
                                    uint _gesturePlayerWin,
                                    uint _gesturePlayerLose);
 
    uint public idCounter;

    Game[] public arrAllGames;
    uint[] public arrIndexAvailableGames;
    mapping(uint => uint) public idToIndexAvailableGames;
    mapping(uint => mapping(uint => uint)) mappingGameResult;

    constructor() public {
        ceoAddress = msg.sender;

        //[Host Gesture][Guest Gesture]
        mappingGameResult[ROCK][ROCK] = GAME_RESULT_DRAW;
        mappingGameResult[ROCK][PAPER] = GAME_RESULT_GUEST_WIN;
        mappingGameResult[ROCK][SCISSOR] = GAME_RESULT_HOST_WIN;
        mappingGameResult[PAPER][PAPER] = GAME_RESULT_DRAW;
        mappingGameResult[PAPER][SCISSOR] = GAME_RESULT_GUEST_WIN;
        mappingGameResult[PAPER][ROCK] = GAME_RESULT_HOST_WIN;
        mappingGameResult[SCISSOR][SCISSOR] = GAME_RESULT_DRAW;
        mappingGameResult[SCISSOR][ROCK] = GAME_RESULT_GUEST_WIN;
        mappingGameResult[SCISSOR][PAPER] = GAME_RESULT_HOST_WIN;

        idCounter = 0;
    }

    function createGame(bytes32 _hashGestureHost)
        external
        payable
    {
        idCounter++;

        Game memory game = Game({
            id: idCounter,
            state: GAME_STATE_AVAILABLE_TO_JOIN,
            timeExpire: 0,
            valueBet: msg.value,
            addressHost: msg.sender,
            hashGestureHost: _hashGestureHost,
            addressGuest: DUMMY_ADDRESS,
            gestureGuest: 0
        });

        arrAllGames.push(game);
        arrIndexAvailableGames.push(arrAllGames.length - 1);
        idToIndexAvailableGames[game.id] = arrIndexAvailableGames.length - 1;

        emit LogCreateGameSuccessed(game.id, game.valueBet);
    }

    function joinGame(uint _id, uint _gestureGuest)
        external
        payable
        verifiedGameAvailableToJoin(_id)
        verifiedGameId(_id)
        validGesture(_gestureGuest)
    {
        Game storage game = arrAllGames[arrIndexAvailableGames[idToIndexAvailableGames[_id]]];

        require(msg.sender != game.addressHost, "RPSCore::joinGame: Can't join game cretead by host");
        require(msg.value == game.valueBet, "RPSCore::joinGame: Value bet to battle not extractly with value bet of host");
       
        game.addressGuest = msg.sender;
        game.gestureGuest = _gestureGuest;
        game.state = GAME_STATE_WAITING_HOST_REVEAL;
        game.timeExpire = now + TIME_GAME_EXPIRE;

        emit LogJoinGameSuccessed(game.id, game.addressHost);
    }

    function revealGameByHost(uint _id, uint _gestureHost, bytes32 _secretKey)
        external
        payable
        verifiedGameId(_id) 
    {
        Game storage game = arrAllGames[arrIndexAvailableGames[idToIndexAvailableGames[_id]]];
        bytes32 hashGestureHost = getHashGesture(_gestureHost, _secretKey);

        require(game.state == GAME_STATE_WAITING_HOST_REVEAL, "Game not in state waiting reveal");
        require(now <= game.timeExpire, "Host time reveal ended");
        require(game.addressHost == msg.sender, "You're not host this game");

        uint result = GAME_RESULT_DRAW;
        bool isHostCheat = false;

        if(game.hashGestureHost != hashGestureHost) {
            result = GAME_RESULT_GUEST_WIN_BY_HOST_CHEAT;
            isHostCheat = true;
        }

        if(isHostCheat == false) {
            //Result: [Draw] => Return money to host and guest players (No fee)
            if(_gestureHost == game.gestureGuest) {
                result = GAME_RESULT_DRAW;
                sendPayment(game.addressHost, game.valueBet);
                sendPayment(game.addressGuest, game.valueBet);
                closeGame(_id);
                emit LogRevealGameSuccessed(_id,
                                            result,
                                            game.addressHost,
                                            game.addressGuest,
                                            0,
                                            0,
                                            _gestureHost, 
                                            game.gestureGuest);
            }
            else
            {
                result = mappingGameResult[_gestureHost][game.gestureGuest];

                if(result == GAME_RESULT_HOST_WIN) {
                    //Result: [Win] => Return money to winner (Winner will pay 1% fee)
                    uint tipValue = getTipValue(game.valueBet);

                    addTipForDeveloper(tipValue);

                    sendPayment(game.addressHost, game.valueBet * 2 - tipValue);
                    closeGame(_id);    
                    emit LogRevealGameSuccessed(_id,
                                                GAME_RESULT_HOST_WIN,
                                                game.addressHost,
                                                game.addressGuest,
                                                game.valueBet - tipValue,
                                                game.valueBet,
                                                _gestureHost, 
                                                game.gestureGuest);        
                }
                else
                    if(result == GAME_RESULT_GUEST_WIN || result == GAME_RESULT_GUEST_WIN_BY_HOST_CHEAT) {
                        //Result: [Win] => Return money to winner (Winner will pay 1% fee)
                        uint cachedGestureHost = _gestureHost;
                        uint tipValue = getTipValue(game.valueBet);

                        addTipForDeveloper(tipValue);

                        sendPayment(game.addressGuest, game.valueBet * 2 - tipValue);
                        closeGame(_id);
                        emit LogRevealGameSuccessed(_id,
                                                    result,
                                                    game.addressGuest,
                                                    game.addressHost,
                                                    game.valueBet - tipValue,
                                                    game.valueBet,
                                                    game.gestureGuest, 
                                                    cachedGestureHost);
                    }
            }
        }
    }

    function revealGameByGuest(uint _id)
        external
        payable
        verifiedGameId(_id)
    {
        Game storage game = arrAllGames[arrIndexAvailableGames[idToIndexAvailableGames[_id]]];

        require(game.state == GAME_STATE_WAITING_HOST_REVEAL, "RPSCore::revealGameByGuest: Game not in state waiting reveal");
        require(now > game.timeExpire, "RPSCore::revealGameByGuest: Time reveal of host not ended");
        require(game.addressGuest == msg.sender, "RPSCore::revealGameByGuest: You're not guest this game");

        uint tipValue = getTipValue(game.valueBet);

        addTipForDeveloper(tipValue);
        sendPayment(game.addressGuest, game.valueBet * 2 - tipValue);
        closeGame(_id);

        emit LogRevealGameSuccessed(_id,
                                    GAME_RESULT_GUEST_WIN,
                                    game.addressGuest,
                                    game.addressHost,
                                    game.valueBet - tipValue,
                                    game.valueBet,
                                    game.gestureGuest, 
                                    0);
    }

    function hostCloseGame(uint _id)
        external
        payable
        verifiedGameAvailableToJoin(_id)
    {
        Game storage game = arrAllGames[arrIndexAvailableGames[idToIndexAvailableGames[_id]]];

        require(msg.sender == game.addressHost, "Verify host of game failed!");

        sendPayment(game.addressHost, game.valueBet);
        closeGame(_id);
        emit LogCloseGameSuccessed(_id, game.valueBet);
    }

    function closeGame(uint _id) private {
        Game storage game = arrAllGames[arrIndexAvailableGames[idToIndexAvailableGames[_id]]];

        game.state = GAME_STATE_CLOSED;
        removeIndexOfGameFromArrayIndexAvailableGames(_id);
    }

    function removeIndexOfGameFromArrayIndexAvailableGames(uint _id) private {
        uint indexRemove = idToIndexAvailableGames[_id];
        if(arrIndexAvailableGames.length > 1 && (indexRemove != arrIndexAvailableGames.length - 1)) {
            uint indexWillReplace = arrIndexAvailableGames[arrIndexAvailableGames.length - 1];
            arrIndexAvailableGames[indexRemove] = indexWillReplace;
            idToIndexAvailableGames[arrAllGames[indexWillReplace].id] = indexRemove;
        }

        delete arrIndexAvailableGames[arrIndexAvailableGames.length - 1];
        delete idToIndexAvailableGames[_id];
        arrIndexAvailableGames.length--;
    }

    function getArrIndexAvailableGames()
        public
        view 
        returns (uint[] memory) 
    {
        return arrIndexAvailableGames;
    }

    function getLengthArrIndexAvailableGames()
        public
        view
        returns (uint)
    {
        return arrIndexAvailableGames.length;
    }

    function getTipValue(uint _valueWin) private pure returns(uint) {
        return _valueWin * DEVELOPER_TIP_PERCENT / 100;
    }

    function sendPayment(address payable _receiver, uint _amount) private {
        _receiver.transfer(_amount);
    }

    function getHashGesture(uint _gesture, bytes32 _secretKey) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_gesture, _secretKey));
    }

    modifier validGesture(uint _gesture) {
        require (_gesture == ROCK || _gesture == PAPER || _gesture == SCISSOR, "Invalid gesture!");
        _;
    }

    modifier verifiedGameAvailableToJoin(uint _id) {
        require(arrAllGames[arrIndexAvailableGames[idToIndexAvailableGames[_id]]].state == GAME_STATE_AVAILABLE_TO_JOIN, "Game not available!");
        _;
    }

    modifier verifiedGameId(uint _id) {
        require(_id > 0 && idToIndexAvailableGames[_id] >= 0, "Game ID not verify!");
        _;
    }
}