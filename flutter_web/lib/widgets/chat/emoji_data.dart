import 'package:flutter/material.dart';

enum EmojiCategory {
  recent,
  smileys,
  people,
  gestures,
  animals,
  food,
  activities,
  travel,
  objects,
  symbols,
  dental,
}

class CustomEmoji {
  final String shortcode;
  final String assetPath;
  final String label;
  const CustomEmoji({required this.shortcode, required this.assetPath, required this.label});
}

class EmojiData {
  // DFS / Dental custom emojis (shortcodes stored as text)
  static const List<CustomEmoji> customEmojisDental = [
    CustomEmoji(shortcode: ':dfs_tooth:', assetPath: 'assets/emojis/dfs_tooth.png', label: 'Tooth'),
    CustomEmoji(shortcode: ':dfs_bur:', assetPath: 'assets/emojis/dfs_bur.png', label: 'Bur / Rotary'),
    CustomEmoji(shortcode: ':dfs_diamond:', assetPath: 'assets/emojis/dfs_diamond.png', label: 'Diamond'),
    CustomEmoji(shortcode: ':dfs_shield:', assetPath: 'assets/emojis/dfs_shield.png', label: 'Quality / Shield'),
    CustomEmoji(shortcode: ':dfs_clean:', assetPath: 'assets/emojis/dfs_clean.png', label: 'Clean / Hygiene'),
    CustomEmoji(shortcode: ':dfs_mdr:', assetPath: 'assets/emojis/dfs_mdr.png', label: 'MDR'),
    CustomEmoji(shortcode: ':dfs_warning:', assetPath: 'assets/emojis/dfs_warning.png', label: 'Warning / CAPA'),
    CustomEmoji(shortcode: ':dfs_blue_dot:', assetPath: 'assets/emojis/dfs_blue_dot.png', label: 'DFS Blue'),
  ];

  static final Map<String, CustomEmoji> customEmojiByCode = {
    for (final e in customEmojisDental) e.shortcode: e,
  };

  static IconData categoryIcon(EmojiCategory c) {
    switch (c) {
      case EmojiCategory.recent:
        return Icons.access_time;
      case EmojiCategory.smileys:
        return Icons.emoji_emotions;
      case EmojiCategory.people:
        return Icons.person;
      case EmojiCategory.gestures:
        return Icons.back_hand;
      case EmojiCategory.animals:
        return Icons.pets;
      case EmojiCategory.food:
        return Icons.restaurant;
      case EmojiCategory.activities:
        return Icons.sports_esports;
      case EmojiCategory.travel:
        return Icons.flight;
      case EmojiCategory.objects:
        return Icons.lightbulb;
      case EmojiCategory.symbols:
        return Icons.favorite;
      case EmojiCategory.dental:
        return Icons.medical_services;
    }
  }

  static const Map<EmojiCategory, List<String>> emojiCategories = {
    EmojiCategory.smileys: [
      '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😙',
      '🥲','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','🫥','😏','😒',
      '🙄','😬','😮‍💨','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮','🤧','🥵','🥶','🥴',
      '😵','😵‍💫','🤯','🤠','🥳','🥸','😎','🤓','🧐','😕','😟','🙁','☹️','😮','😯','😲','😳','🥺',
      '😦','😧','😨','😰','😥','😢','😭','😱','😖','😣','😞','😓','😩','😫','🥱','😤','😡','😠','🤬',
      '😈','👿','💀','☠️','💩','🤡','👹','👺','👻','👽','👾','🤖','🎃','😺','😸','😹','😻','😼','😽',
      '🙀','😿','😾'
    ],

    EmojiCategory.people: [
      '👶','🧒','👦','👧','🧑','👨','👩','🧔','🧔‍♂️','🧔‍♀️','👱','👱‍♂️','👱‍♀️','👴','👵',
      '🧓','👨‍🦰','👩‍🦰','👨‍🦱','👩‍🦱','👨‍🦳','👩‍🦳','👨‍🦲','👩‍🦲',
      '🧑‍⚕️','👨‍⚕️','👩‍⚕️','🧑‍🎓','👨‍🎓','👩‍🎓','🧑‍🏫','👨‍🏫','👩‍🏫',
      '🧑‍💼','👨‍💼','👩‍💼','🧑‍🔧','👨‍🔧','👩‍🔧','🧑‍🏭','👨‍🏭','👩‍🏭',
      '🧑‍🔬','👨‍🔬','👩‍🔬','🧑‍💻','👨‍💻','👩‍💻','🧑‍🎨','👨‍🎨','👩‍🎨',
      '🧑‍🚒','👨‍🚒','👩‍🚒','🧑‍✈️','👨‍✈️','👩‍✈️','🧑‍🚀','👨‍🚀','👩‍🚀',
      '🧑‍⚖️','👨‍⚖️','👩‍⚖️','👮','👮‍♂️','👮‍♀️','🕵️','🕵️‍♂️','🕵️‍♀️',
      '💂','💂‍♂️','💂‍♀️','🥷','🧑‍🌾','👨‍🌾','👩‍🌾'
    ],

    EmojiCategory.gestures: [
      '👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','🖕','👇','☝️',
      '👍','👎','✊','👊','🤛','🤜','👏','🙌','👐','🤲','🤝','🙏','💪','🦾','🫶','🫰','✍️'
    ],

    EmojiCategory.animals: [
      '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐻‍❄️','🐨','🐯','🦁','🐮','🐷','🐽','🐸','🐵','🙈','🙉','🙊',
      '🐔','🐧','🐦','🐤','🐣','🐥','🦆','🦅','🦉','🦇','🐺','🐗','🐴','🦄','🐝','🪲','🐛','🦋','🐌','🐞',
      '🐢','🐍','🦎','🐙','🦑','🦐','🦀','🐡','🐠','🐟','🐬','🦈','🐳','🐋','🦭',
      '🐊','🦓','🦍','🦧','🐘','🦛','🦏','🐪','🐫','🦒','🦘','🦬','🐃','🐂','🐄','🐎','🐖','🐏','🐑','🐐',
      '🦌','🐕','🐩','🦮','🐕‍🦺','🐈','🐈‍⬛','🪶','🐓','🦃','🦚','🦜','🦢','🦩','🕊️','🐇','🦝','🦨','🦡','🦫','🦦','🦥'
    ],

    EmojiCategory.food: [
      '🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆',
      '🥑','🥦','🥬','🥒','🌶️','🫑','🌽','🥕','🫒','🧄','🧅','🥔','🍠','🫘','🥜','🌰',
      '🍞','🥐','🥖','🫓','🥨','🥯','🥞','🧇','🧀','🍖','🍗','🥩','🥓','🍔','🍟','🍕','🌭','🥪','🌮','🌯',
      '🥙','🧆','🥚','🍳','🥘','🍲','🫕','🥣','🥗','🍿','🧈','🧂',
      '🍣','🍤','🍙','🍚','🍛','🍜','🍝','🍠','🍢','🍡','🥟','🦪','🍱','🥡',
      '🍦','🍧','🍨','🍩','🍪','🎂','🍰','🧁','🥧','🍫','🍬','🍭','🍮','🍯',
      '☕','🫖','🍵','🥛','🧋','🧃','🧉','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🧊'
    ],

    EmojiCategory.activities: [
      '⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🥏','🎱','🪀','🏓','🏸','🏒','🏑','🥍','🏏','⛳','🪁',
      '🏹','🎣','🤿','🥊','🥋','🎽','🛹','🛼','🛷','⛸️','🎿','⛷️','🏂',
      '🎮','🕹️','🎲','♟️','🧩','🎯','🎳','🎰',
      '🎸','🎹','🎺','🎷','🪗','🥁','🪘','🎻','🎤','🎧','🎼',
      '🎨','🖌️','🖍️','🎬','🎥','🎞️'
    ],

    EmojiCategory.travel: [
      '🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🛵','🏍️','🚲','🛴','🚨',
      '🚆','🚄','🚅','🚈','🚇','🚉','🚊','🚝','🚞','🚋',
      '✈️','🛫','🛬','🛩️','🚁','🚀','🛸',
      '⛵','🛥️','🚤','🛳️','🚢',
      '🗺️','🧭','🏔️','⛰️','🌋','🗻','🏕️','🏖️','🏜️','🏝️','🏟️','🏛️','🕌','🕍','⛩️','🕋','🏰','🏯',
      '🌍','🌎','🌏','🗽','🗼','🗿'
    ],

    EmojiCategory.objects: [
      '⌚','📱','📲','💻','🖥️','🖨️','⌨️','🖱️','🖲️','🕹️','💽','💾','💿','📀','📷','📸','📹','🎥','📞','☎️','📟',
      '📠','📺','📻','🎙️','🎚️','🎛️','🧭','⏱️','⏲️','⏰','🕰️',
      '🔋','🪫','🔌','💡','🔦','🕯️','🪔','🧯','🛢️',
      '💰','🪙','💳','🧾','💎','⚖️','🔧','🪛','🔨','🪓','⛏️','🛠️','🧰','🪜','🧲',
      '🧪','🧫','🧬','🔬','🔭','📡',
      '📦','📁','📂','🗂️','🗃️','🗄️','📋','📌','📍','📎','🖇️','✂️','🖊️','🖋️','✒️','✏️','📝','📖','📚','📒','📓','📔','📕','📗','📘','📙',
      '🔒','🔓','🔏','🔐','🔑','🗝️',
      '🧴','🧼','🪥','🪒','🧻','🩹','💊','🩺','🩻','🧽','🪣'
    ],

    EmojiCategory.symbols: [
      '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❤️‍🔥','❤️‍🩹','💖','💗','💓','💞','💕','💟',
      '✨','⭐','🌟','💫','🔥','💥','💢','💯','✅','☑️','✔️','✖️','❌','❎','➕','➖','➗','➰','➿',
      '⚠️','🚫','⛔','🛑','❗','❓','⁉️','‼️','🔔','🔕','📣','📢',
      '🔴','🟠','🟡','🟢','🔵','🟣','⚫','⚪','🟤',
      '♻️','⚕️','☮️','☯️','✝️','☪️','🕉️','☸️','✡️','🔯','🛐',
      '🔺','🔻','🔸','🔹','🔶','🔷','🔳','🔲'
    ],
  };
}
