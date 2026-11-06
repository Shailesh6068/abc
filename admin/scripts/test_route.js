async function testRoutes() {
  const start = { lat: 18.6534, lng: 73.7663 };
  const dest = { lat: 18.6490, lng: 73.7668 };

  // 1. Test OSRM Foot Routing (Free, instant, real street routing)
  try {
    const osrmUrl = `https://router.project-osrm.org/route/v1/foot/${start.lng},${start.lat};${dest.lng},${dest.lat}?overview=full&geometries=geojson`;
    const res = await fetch(osrmUrl);
    const data = await res.json();
    console.log('OSRM response:', data.code, 'Road Distance (m):', data.routes?.[0]?.distance, 'points count:', data.routes?.[0]?.geometry?.coordinates?.length);
  } catch (e) {
    console.log('OSRM err:', e.message);
  }

  // 2. Test Google Directions API with user key
  try {
    const key = 'AIzaSyDmDUvCYOhDgSiq6lEx1R7V4JepIyHB0KQ';
    const gUrl = `https://maps.googleapis.com/maps/api/directions/json?origin=${start.lat},${start.lng}&destination=${dest.lat},${dest.lng}&mode=walking&key=${key}`;
    const res = await fetch(gUrl);
    const data = await res.json();
    console.log('Google Directions status:', data.status, 'Distance:', data.routes?.[0]?.legs?.[0]?.distance?.text);
  } catch (e) {
    console.log('Google err:', e.message);
  }
}
testRoutes();
