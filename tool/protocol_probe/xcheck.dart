// ignore_for_file: avoid_print, avoid_relative_lib_imports
// Dev-only cross-check script, see README.md in this directory.
import '../../lib/networking/command_packet.dart';
import '../../lib/networking/command_payloads.dart';
String hx(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
void main() {
  for (final db in [-40.0, -40.5, -41.0]) {
    print('vol $db pc=7 cc=7: ${hx(CommandPacket(packetCounter: 7, commandCounter: 7, payload: CommandPayloads.setVolume(db)).encode().sublist(0, 14))}');
  }
  for (final i in [0, 1, 2, 3, 4, 5, 9, 14]) {
    print('src $i pc=0x1234 cc=0x5678: ${hx(CommandPacket(packetCounter: 0x1234, commandCounter: 0x5678, payload: CommandPayloads.selectSource(i)).encode().sublist(0, 14))}');
  }
  print('muteOn pc=1 cc=1: ${hx(CommandPacket(packetCounter: 1, commandCounter: 1, payload: CommandPayloads.muteOn).encode().sublist(0, 14))}');
}
