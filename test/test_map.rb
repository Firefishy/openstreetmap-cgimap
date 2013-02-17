#!/usr/bin/env ruby

require 'xml/libxml'
require 'set'
require 'pg'
$LOAD_PATH << File.dirname(__FILE__)
require 'test_functions.rb'

conn = PG.connect(dbname: ARGV[1])
conn.transaction do |tx|
  load_osm_file("#{File.dirname(__FILE__)}/test_map.osm", tx)
end

# bad requests:
['/api/0.6/map',                          # no bbox parameter
 '/api/0.6/map?bbox=',                    # empty bbox parameter
 '/api/0.6/map?bbox=0,0,0',               # not enough numbers
 '/api/0.6/map?bbox=0.1,0.1,-0.1,-0.1',   # negative size bbox
 '/api/0.6/map?bbox=179.9,0,180.1,0.1',   # bbox out of valid range
 '/api/0.6/map?bbox=-180.1,0,-179.9,0.1', # bbox out of valid range
 '/api/0.6/map?bbox=0,89.9,0.1,90.1',     # bbox out of valid range
 '/api/0.6/map?bbox=0,-90.1,0.1,-89.9'    # bbox out of valid range
].each do |req|
  test_request('GET', req, 'HTTP_ACCEPT' => 'text/xml') do |headers, data|
    assert(headers['Status'], '400 Bad Request', "Response status code [#{req}].")
  end
end

# grabbing an empty bounding box is OK, but should just return an 
# OSM document with only a <bounds> element in it.
test_request('GET', '/api/0.6/map?bbox=-0.01,-0.01,-0.0005,-0.0005') do |headers, data|
  assert(headers["Status"], "200 OK", "Response status code.")
  assert(headers["Content-Type"], "text/xml; charset=utf-8", "Response content type.")

  doc = XML::Parser.string(data).parse
  assert(doc.root.name, "osm", "Document root element.")
  children = doc.root.children.select {|n| n.element?}
  assert(children.size, 1, "Number of children of the <osm> element.")

  bounds = children[0]
  assert(bounds.name, "bounds", "Name of <osm> child.")
  assert(bounds['minlat'], '-0.0100000', 'Bounds minimum latitude parameter.')
  assert(bounds['minlon'], '-0.0100000', 'Bounds minimum longitude parameter.')
  assert(bounds['maxlat'], '-0.0005000', 'Bounds maximum latitude parameter.')
  assert(bounds['maxlon'], '-0.0005000', 'Bounds maximum longitude parameter.')
end

# tests grabbing a single node which isn't connected to anything else,
# so should return this node only.
test_request('GET', '/api/0.6/map?bbox=-0.0005,-0.0005,0.0005,0.0005') do |headers, data|
  assert(headers["Status"], "200 OK", "Response status code.")
  assert(headers["Content-Type"], "text/xml; charset=utf-8", "Response content type.")

  doc = XML::Parser.string(data).parse
  assert(doc.root.name, "osm", "Document root element.")
  children = doc.root.children.select {|n| n.element?}
  assert(children.size, 2, "Number of children of the <osm> element.")

  # first child should be <bounds>
  assert(children[0].name, 'bounds', 'First element in map response should be bounds.')

  # only other element should be the single node.
  node = children[1]
  assert(node.name, "node", "Name of <osm> child.")
  assert(node["id"].to_i, 1, "ID of node")
  assert(node["lat"], "0.0000000", "Latitude attribute")
  assert(node["lon"], "0.0000000", "Longitude attribute")
  assert(node["user"], "user_1", "User name")
  assert(node["uid"].to_i, 1, "User ID")
  assert(node["visible"], "true", "Visibility attribute")
  assert(node["version"].to_i, 1, "Version attribute")
  assert(node["changeset"].to_i, 1, "Changeset ID")
  assert(node["timestamp"], "2013-02-16T19:02:00Z", "Timestamp")
end
