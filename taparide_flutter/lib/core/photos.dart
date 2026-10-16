/// Real photographs bundled with the app (all openly licensed, see [photoCredits]).
enum AppPhoto {
  cityGateAerial('city_gate_aerial'),
  cityGateWelcome('city_gate_welcome'),
  lightRail('abuja_light_rail'),
  brtLifeCamp('brt_life_camp'),
  taxis('abuja_taxis'),
  wusePanorama('wuse_panorama'),
  asoRockExpressway('aso_rock_expressway'),
  asoRockCity('aso_rock_city'),
  expressway('abuja_expressway'),
  evSuv('ev_suv'),
  evCharging('ev_charging'),
  brtBerger('brt_berger'),
  keke('keke_abuja');

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
  PhotoCredit(photo: AppPhoto.cityGateWelcome, title: 'Abuja City Gate 02', author: 'Jummy001', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Abuja_City_Gate_02.jpg'),
  PhotoCredit(photo: AppPhoto.lightRail, title: 'VLT de Abuja', author: 'Paz e concórdia', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:VLT_de_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.brtLifeCamp, title: 'Passengers boarding BRT at Life Camp, Abuja', author: 'Dike Chukwuma', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Passengers_boarding_BRT_at_Life_Camp,_Abuja_by_Dike_Chukwuma.jpg'),
  PhotoCredit(photo: AppPhoto.taxis, title: 'Abuja painted taxis', author: 'Dike Chukwuma', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Abuja_painted_Taxis_by_Dike_Chukwuma.jpg'),
  PhotoCredit(photo: AppPhoto.wusePanorama, title: 'Panorama view of Wuse 2, Abuja', author: 'Biggiepopa', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Panorama_view_of_wuse_2,_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.asoRockExpressway, title: 'Central Business District Abuja', author: 'FaridhaSL', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Central_Business_District_Abuja.jpg'),
  PhotoCredit(photo: AppPhoto.asoRockCity, title: 'Abuja hotel view', author: 'Bryn Pinzgauer', license: 'CC BY 2.0', source: 'https://commons.wikimedia.org/wiki/File:Abuja_hotel_view_(7955265376).jpg'),
  PhotoCredit(photo: AppPhoto.expressway, title: 'Beautiful road network in Abuja Nigeria', author: 'Igboanude', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Beautiful_road_network_in_Abuja_Nigeria.jpg'),
  PhotoCredit(photo: AppPhoto.evSuv, title: 'Hyundai Kona Electric (SX2)', author: 'Alexander-93', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Hyundai_Kona_Electric_(SX2)_1X7A1554.jpg'),
  PhotoCredit(photo: AppPhoto.evCharging, title: 'Car2Go charging station, Stuttgart', author: 'Julian Herzog', license: 'CC BY 4.0', source: 'https://commons.wikimedia.org/wiki/File:Car2Go_Charging_Station_Stuttgart_2013_01.jpg'),
  PhotoCredit(photo: AppPhoto.brtBerger, title: 'BRT park at Berger Bridge in Abuja', author: 'Dike Chukwuma', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:BRT_park_at_Berger_Brigdge_in_Abuja_by_Dike_Chukwuma.jpg'),
  PhotoCredit(photo: AppPhoto.keke, title: 'Transportation in Abuja 1', author: 'Minette Lontsie', license: 'CC BY-SA 4.0', source: 'https://commons.wikimedia.org/wiki/File:Transportation_in_Abuja_1.jpg'),
];
