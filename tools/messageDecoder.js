var BitSet = require('bitset');
var Sprintf = require('sprintf-js').sprintf;
var BinaryParser = require('binary-parser').Parser;

var msg = "Z0C9704420F42610000000024D6\r\n";
msg = msg.replace(/\n/, '')
msg = msg.replace(/\r/, '')
var rawLength = msg.length;

var rssi = parseInt(msg.slice(-2), 16)

if (rssi >= 128){
    rssi = (rssi - 256) / 2 - 74;
}else{
    rssi = rssi / 2 - 74;
}

console.log("RSSI: "+rssi);

var data = msg.split(/Z(..)(..)(..)(..)(......)(......)(..)(.*)/)
data.shift();

console.log("--> Data after split");
console.log(data);

if ( data.length <= 1)
    console.log("--> cannot split packet")

var length = parseInt(data[0],16);
var lengthConverted = 2 * length + 3;

console.log("Packet Length delivered: "+length);
console.log("Length converted: "+lengthConverted);
console.log("Raw Packet Length: "+rawLength);

if (2 * length + 3 != msg.length){
    console.log("--> packet length missmatch");
    return false;
}else{
    console.log("--> packet length ok")
}

console.log("MessageCounter: "+parseInt(data[1],16));
console.log("Flag: "+parseInt(data[2],16));
console.log("GroupId: "+parseInt(data[6],16));
console.log("RawType: "+data[3]);
console.log("Source: "+data[4]);
console.log("Dest: "+data[5]);
console.log("RawPayload: "+data[7]);
