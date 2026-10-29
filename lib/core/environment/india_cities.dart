/// Cities for air & heat outlooks. Picking a city needs NO location
/// permission — HUX never tracks where the user is for this feature.
/// Coordinates are city-centre approximations (forecast grids are
/// ~10–45 km anyway).
library;

/// IMD uses different heat-wave thresholds for plains, coastal and
/// hill stations.
enum Terrain { plains, coastal, hills }

class IndiaCity {
  final String name;
  final double lat;
  final double lon;
  final Terrain terrain;
  const IndiaCity(this.name, this.lat, this.lon, this.terrain);
}

const indiaCities = <IndiaCity>[
  IndiaCity('Ahmedabad', 23.02, 72.57, Terrain.plains),
  IndiaCity('Amritsar', 31.63, 74.87, Terrain.plains),
  IndiaCity('Bengaluru', 12.97, 77.59, Terrain.plains),
  IndiaCity('Bhopal', 23.26, 77.41, Terrain.plains),
  IndiaCity('Bhubaneswar', 20.30, 85.82, Terrain.plains),
  IndiaCity('Chandigarh', 30.73, 76.78, Terrain.plains),
  IndiaCity('Chennai', 13.08, 80.27, Terrain.coastal),
  IndiaCity('Coimbatore', 11.02, 76.96, Terrain.plains),
  IndiaCity('Dehradun', 30.32, 78.03, Terrain.plains),
  IndiaCity('Delhi', 28.61, 77.21, Terrain.plains),
  IndiaCity('Goa (Panaji)', 15.49, 73.83, Terrain.coastal),
  IndiaCity('Guwahati', 26.14, 91.74, Terrain.plains),
  IndiaCity('Hyderabad', 17.39, 78.49, Terrain.plains),
  IndiaCity('Indore', 22.72, 75.86, Terrain.plains),
  IndiaCity('Jaipur', 26.91, 75.79, Terrain.plains),
  IndiaCity('Kanpur', 26.45, 80.33, Terrain.plains),
  IndiaCity('Kochi', 9.93, 76.27, Terrain.coastal),
  IndiaCity('Kolkata', 22.57, 88.36, Terrain.plains),
  IndiaCity('Lucknow', 26.85, 80.95, Terrain.plains),
  IndiaCity('Madurai', 9.93, 78.12, Terrain.plains),
  IndiaCity('Mangaluru', 12.91, 74.86, Terrain.coastal),
  IndiaCity('Mumbai', 19.08, 72.88, Terrain.coastal),
  IndiaCity('Mysuru', 12.30, 76.64, Terrain.plains),
  IndiaCity('Nagpur', 21.15, 79.09, Terrain.plains),
  IndiaCity('Nashik', 20.00, 73.79, Terrain.plains),
  IndiaCity('Patna', 25.59, 85.14, Terrain.plains),
  IndiaCity('Pune', 18.52, 73.86, Terrain.plains),
  IndiaCity('Raipur', 21.25, 81.63, Terrain.plains),
  IndiaCity('Ranchi', 23.34, 85.31, Terrain.plains),
  IndiaCity('Shimla', 31.10, 77.17, Terrain.hills),
  IndiaCity('Srinagar', 34.08, 74.80, Terrain.hills),
  IndiaCity('Surat', 21.17, 72.83, Terrain.coastal),
  IndiaCity('Thiruvananthapuram', 8.52, 76.94, Terrain.coastal),
  IndiaCity('Tirupati', 13.63, 79.42, Terrain.plains),
  IndiaCity('Varanasi', 25.32, 82.97, Terrain.plains),
  IndiaCity('Vijayawada', 16.51, 80.65, Terrain.plains),
  IndiaCity('Visakhapatnam', 17.69, 83.22, Terrain.coastal),
  IndiaCity('Warangal', 17.97, 79.59, Terrain.plains),
];

IndiaCity? cityNamed(String? name) {
  for (final c in indiaCities) {
    if (c.name == name) return c;
  }
  return null;
}
