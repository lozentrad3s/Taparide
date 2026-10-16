/// Real photographs bundled with the app (all openly licensed, see [photoCredits]).
enum AppPhoto {
  cityGateAerial('city_gate_aerial'),
  lightRail('abuja_light_rail'),
  taxis('abuja_taxis'),
  asoRockExpressway('aso_rock_expressway'),
  expressway('abuja_expressway'),
  evSuv('ev_suv'),
  evPlug('ev_plug'),
  brtBerger('brt_berger');

  const AppPhoto(this.file);
  final String file;

  String get asset => 'assets/photos/$file.jpg';
}

class PhotoCredit {
  const PhotoCredit({required this.photo, required this.title, required this.author, required this.license, required this.source});
  final AppPhoto photo;
  final String title;
  final String author;
  final String license;
  final String source;
}

const photoCredits = <PhotoCredit>[
  PhotoCredit(photo: AppPhoto.cityGateAerial, title: 'Aerial landscape of Abuja City Gate', author: 'Jummy001', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Aerial_landscape_of_Abuja_City_Gate.jpg'),
  PhotoCredit(photo: AppPhoto.lightRail, title: 'VLT de Abuja', author: 'Paz e concórdia', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:VLT_de_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.taxis, title: 'Abuja painted taxis', author: 'Dike Chukwuma', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Abuja_painted_Taxis_by_Dike_Chukwuma.jpg'),
  PhotoCredit(photo: AppPhoto.asoRockExpressway, title: 'Central Business District Abuja', author: 'FaridhaSL', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Central_Business_District_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.expressway, title: 'Beautiful road network in Abuja Nigeria', author: 'Igboanude', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Beautiful_road_network_in_Abuja_Nigeria.jpg'),
  PhotoCredit(photo: AppPhoto.evSuv, title: 'Hyundai Kona Electric (SX2)', author: 'Alexander-93', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Hyundai_Kona_Electric_(SX2)_1X7A1554.jpg'),
  PhotoCredit(photo: AppPhoto.evPlug, title: 'Close-up of an electric car charging', author: 'Ivan Radic', license: 'CC BY 2.0', source: 'https://commons.wikimedia.org/wiki/File:Close-up_of_an_electric_car_charging._Traffic_lights_in_a_blurry_background.jpg'),
  PhotoCredit(photo: AppPhoto.brtBerger, title: 'BRT park at Berger Bridge in Abuja', author: 'Dike Chukwuma', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:BRT_park_at_Berger_Brigdge_in_Abuja_by_Dike_Chukwuma.jpg'),
];
