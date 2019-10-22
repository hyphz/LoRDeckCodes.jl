"""
    DeckEncoder
"""
module DeckEncoder # LoRDeckCodes

using ..LoRDeckCodes: Base32, VarintTranslator, Deck, Card

const DECK_CODE_FORMAT = 1
const MAX_KNOWN_VERSION = 1
const CARD_CODE_LENGTH = 7

const FactionCodeToIntIdentifier = Dict{String,Int}(
    "DE" => 0,
    "FR" => 1,
    "IO" => 2,
    "NX" => 3,
    "PZ" => 4,
    "SI" => 5,
)

const IntIdentifierToFactionCode = Dict{Int,String}(
    0 => "DE",
    1 => "FR",
    2 => "IO",
    3 => "NX",
    4 => "PZ",
    5 => "SI",
)

"""
    encode_deck(cards::Vector{Card})::String
"""
function encode_deck(cards::Vector{Card})::String
    encode_deck(cards, MAX_KNOWN_VERSION)
end

"""
    encode_deck(deck::Deck)::String
"""
function encode_deck(deck::Deck)::String
    encode_deck(deck.cards, deck.version)
end

function encode_deck(cards::Vector{Card}, version::UInt8)::String
    stream = IOBuffer()
    !isvalid(cards) && throw(ArgumentException("The provided deck contains invalid card codes."))
    format_and_version = UInt8((DECK_CODE_FORMAT << 4) | version)
    write(stream, format_and_version)
    of3 = Vector{Card}()
    of2 = Vector{Card}()
    of1 = Vector{Card}()
    ofN = Vector{Card}()
    for card in cards
        if card.count == 3
            push!(of3, card)
        elseif card.count == 2
            push!(of2, card)
        elseif card.count == 1
            push!(of1, card)
        elseif card.count < 1
            throw(ArgumentException(string("Invalid count of ", card.count, " for card ", card.code)))
        else
            push!(ofN, card)
        end
    end
    groupedOf3s = getGroupedOfs(of3)
    groupedOf2s = getGroupedOfs(of2)
    groupedOf1s = getGroupedOfs(of1)
    encodeGroupOf(stream, sortGroupOf(groupedOf3s))
    encodeGroupOf(stream, sortGroupOf(groupedOf2s))
    encodeGroupOf(stream, sortGroupOf(groupedOf1s))
    encodeNOfs(stream, sort(ofN, by = c -> c.code))
    seekstart(stream)
    Base32.encode(read(stream))
end

function getGroupedOfs(list::Vector{Card})::Vector{Vector{Card}}
    result = Vector{Vector{Card}}()
    while !isempty(list)
        currentSet = Vector{Card}()
        firstCard = first(list)
        push!(currentSet, firstCard)
        deleteat!(list, 1)
        for i in length(list):-1:1
            currentCard = list[i]
            if currentCard.set == firstCard.set && currentCard.faction == firstCard.faction
                push!(currentSet, currentCard)
                deleteat!(list, i)
            end
        end
        push!(result, currentSet)
    end
    result
end

function sortGroupOf(group::Vector{Vector{Card}})::Vector{Vector{Card}}
    groupOf = sort(group, by = g -> length(g))
    for i = 1:length(groupOf)
        groupOf[i] = sort(groupOf[i], by = c -> c.code)
    end
    groupOf
end

function encodeGroupOf(stream::IOBuffer, groupOf::Vector{Vector{Card}})
    write(stream, VarintTranslator.get_varint(length(groupOf)))
    for currentList in groupOf
        write(stream, VarintTranslator.get_varint(length(currentList)))
        currentCard = first(currentList)
        write(stream, VarintTranslator.get_varint(currentCard.set))
        write(stream, VarintTranslator.get_varint(FactionCodeToIntIdentifier[currentCard.faction]))
        for cd in currentList
            write(stream, VarintTranslator.get_varint(cd.number))
        end
    end
end

function encodeNOfs(stream::IOBuffer, nOfs::Vector{Card})
    for card in nOfs
        write(stream, VarintTranslator.get_varint(card.count))
        write(stream, VarintTranslator.get_varint(card.set))
        write(stream, VarintTranslator.get_varint(FactionCodeToIntIdentifier[card.faction]))
        write(stream, VarintTranslator.get_varint(card.number))
    end
end

function isvalid(cards::Vector{Card})::Bool
    true
end

function decode_deck(deckcode::String)::Deck
    bytes = Base32.decode(deckcode)
    stream = IOBuffer(bytes)
    (firstbyte,) = read(stream, 1)
    format = firstbyte >> 4
    version = firstbyte & 0x0f
    version > MAX_KNOWN_VERSION && throw(ArgumentException("'The provided code requires a higher version of this library; please update."))
    cards = Vector{Card}()
    for i in 3:-1:1
        numGroupOfs = VarintTranslator.pop_varint(stream)
        for j in 1:numGroupOfs
            numOfsInThisGroup = VarintTranslator.pop_varint(stream)
            set = VarintTranslator.pop_varint(stream)
            faction_id = VarintTranslator.pop_varint(stream)
            for k in 1:numOfsInThisGroup
                 number = VarintTranslator.pop_varint(stream)
                 push!(cards, Card(set, IntIdentifierToFactionCode[faction_id], number, i))
            end
        end
    end
    while !eof(stream)
        count = VarintTranslator.pop_varint(stream)
        set = VarintTranslator.pop_varint(stream)
        faction_id = VarintTranslator.pop_varint(stream)
        number = VarintTranslator.pop_varint(stream)
        push!(cards, Card(set, IntIdentifierToFactionCode[faction_id], number, count))
    end
    Deck(cards, version)
end

"""
    Deck(deckcode::String)::Deck
"""
function Deck(deckcode::String)::Deck
    decode_deck(deckcode)
end

function Deck(cards::Vector{Card})::Deck
    Deck(cards, MAX_KNOWN_VERSION)
end

end # module LoRDeckCodes.DeckEncoder
