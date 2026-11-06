import 'dart:io';
import 'dart:convert';

void main() async {
  final client = HttpClient();
  // Using user-agent as requested by OSM/OSRM policy
  final url = Uri.parse('https://router.project-osrm.org/route/v1/foot/73.7915,18.6495;73.7916,18.6436?overview=full&geometries=geojson');
  final request = await client.getUrl(url);
  request.headers.set('User-Agent', 'RaceZone-Mobile/1.0');
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  final data = jsonDecode(body);
  print('Code: ${data["code"]}');
  print('Distance: ${data["routes"][0]["distance"]} meters');
  print('Coords count: ${(data["routes"][0]["geometry"]["coordinates"] as List).length}');
  exit(0);
}
