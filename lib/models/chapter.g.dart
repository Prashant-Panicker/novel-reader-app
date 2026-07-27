part of 'chapter.dart';

// --------------------------------------------------------------------------
// Hand-written Hive TypeAdapter for Chapter.
//
// Written by hand (instead of via build_runner) so the project builds cleanly
// in CI without an extra code-generation step. If you add/remove fields,
// update this file to match the @HiveField indices in chapter.dart.
// --------------------------------------------------------------------------

class ChapterAdapter extends TypeAdapter<Chapter> {
  @override
  final int typeId = 0;

  @override
  Chapter read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Chapter(
      id: fields[0] as String?,
      url: fields[1] as String? ?? '',
      bookTitle: fields[2] as String? ?? '',
      chapterTitle: fields[3] as String? ?? '',
      rawText: fields[4] as String? ?? '',
      translatedText: fields[5] as String? ?? '',
      scrollPosition: (fields[6] as num?)?.toDouble() ?? 0.0,
      savedAt: fields[7] as DateTime?,
      lastReadAt: fields[8] as DateTime?,
      sourceDomain: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Chapter obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.bookTitle)
      ..writeByte(3)
      ..write(obj.chapterTitle)
      ..writeByte(4)
      ..write(obj.rawText)
      ..writeByte(5)
      ..write(obj.translatedText)
      ..writeByte(6)
      ..write(obj.scrollPosition)
      ..writeByte(7)
      ..write(obj.savedAt)
      ..writeByte(8)
      ..write(obj.lastReadAt)
      ..writeByte(9)
      ..write(obj.sourceDomain);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
