import 'package:cloud_firestore/cloud_firestore.dart';

class Geofence {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;
  final bool isActive;
  final DateTime createdAt;
  final String createdBy;
  final String? description;
  final Map<String, dynamic>? metadata;

  Geofence({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.isActive = true,
    required this.createdAt,
    required this.createdBy,
    this.description,
    this.metadata,
  });

  // Create from Firestore document
  factory Geofence.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final GeoPoint geoPoint = data['location'] as GeoPoint;
    
    return Geofence(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Geofence',
      latitude: geoPoint.latitude,
      longitude: geoPoint.longitude,
      radius: (data['radius'] ?? 100.0).toDouble(),
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      description: data['description'],
      metadata: data['metadata'] as Map<String, dynamic>?,
    );
  }

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'location': GeoPoint(latitude, longitude),
      'radius': radius,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'description': description,
      'metadata': metadata,
    };
  }

  // Create a copy with some fields changed
  Geofence copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radius,
    bool? isActive,
    DateTime? createdAt,
    String? createdBy,
    String? description,
    Map<String, dynamic>? metadata,
  }) {
    return Geofence(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
    );
  }
} 