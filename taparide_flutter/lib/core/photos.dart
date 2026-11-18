/// Real photographs bundled with the app: Tap A Ride's own images and openly licensed ones (see [photoCredits]).
enum AppPhoto {
  cityGateAerial('city_gate_aerial'),
  lightRail('abuja_light_rail'),
  tagAlongFriends('tag_along_friends'),
  shareRideRider('share_ride_rider'),
  asoRockExpressway('aso_rock_expressway'),
  expressway('abuja_expressway'),
  evSuv('ev_suv'),
  evCharging('ev_charging'),
  evPlug('ev_plug'),
  brtBerger('brt_berger');

  const AppPhoto(this.file);
  final String file;

  /// Old name kept so existing screens still build; the Wikimedia taxi photo was replaced by Tap A Ride's own Tag Along photo.
  static const taxis = AppPhoto.tagAlongFriends;

  String get asset => 'assets/photos/$file.jpg';
}

/// The one photo used for electric vehicles across the app (EV page hero and cards, home EV card).
/// No Tap A Ride EV photo exists yet: when one is provided, add it to [AppPhoto] and point this at it.
const evPhoto = AppPhoto.evCharging;

class PhotoCredit {
  const PhotoCredit({required this.photo, required this.title, required this.author, required this.license, required this.source});

  /// Tap A Ride's own image (no external source to link to).
  const PhotoCredit.own({required this.photo, required this.title}) : author = 'Tap A Ride', license = "Tap A Ride's own image", source = '';

  final AppPhoto photo;
  final String title;
  final String author;
  final String license;
  final String source;

  bool get isOwn => source.isEmpty;
}

const photoCredits = <PhotoCredit>[
  PhotoCredit.own(photo: AppPhoto.tagAlongFriends, title: 'Friends sharing a Tag Along ride'),
  PhotoCredit.own(photo: AppPhoto.shareRideRider, title: 'Rider sharing her ride'),
  PhotoCredit(photo: AppPhoto.cityGateAerial, title: 'Aerial landscape of Abuja City Gate', author: 'Jummy001', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Aerial_landscape_of_Abuja_City_Gate.jpg'),
  PhotoCredit(photo: AppPhoto.lightRail, title: 'VLT de Abuja', author: 'Paz e concórdia', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:VLT_de_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.asoRockExpressway, title: 'Central Business District Abuja', author: 'FaridhaSL', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Central_Business_District_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.expressway, title: 'Beautiful road network in Abuja Nigeria', author: 'Igboanude', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Beautiful_road_network_in_Abuja_Nigeria.jpg'),
  PhotoCredit(photo: AppPhoto.evSuv, title: 'Hyundai Kona Electric (SX2)', author: 'Alexander-93', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Hyundai_Kona_Electric_(SX2)_1X7A1554.jpg'),
  PhotoCredit(photo: AppPhoto.evCharging, title: 'Hyundai Ioniq 5 charging at Davis Square, November 2025', author: '4300streetcar', license: 'CC BY 4.0', source: 'https://commons.wikimedia.org/wiki/File:Hyundai_Ioniq_5_charging_at_Davis_Square_November_2025_1.jpg'),
  PhotoCredit(photo: AppPhoto.evPlug, title: 'Close-up of an electric car charging', author: 'Ivan Radic', license: 'CC BY 2.0', source: 'https://commons.wikimedia.org/wiki/File:Close-up_of_an_electric_car_charging._Traffic_lights_in_a_blurry_background.jpg'),
  PhotoCredit(photo: AppPhoto.brtBerger, title: 'BRT park at Berger Bridge in Abuja', author: 'Dike Chukwuma', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:BRT_park_at_Berger_Brigdge_in_Abuja_by_Dike_Chukwuma.jpg'),
];
