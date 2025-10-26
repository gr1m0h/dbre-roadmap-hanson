// MongoDB 地理空間インデックス
// 使用方法: mongosh < geospatial_index.js

// 2dsphere インデックス（地球座標系）
db.places.createIndex({ location: "2dsphere" });

// データ挿入（GeoJSON形式）
db.places.insertOne({
    name: "Tokyo Tower",
    location: {
        type: "Point",
        coordinates: [139.7454, 35.6586]  // [経度, 緯度]
    }
});

// 近傍検索
db.places.find({
    location: {
        $near: {
            $geometry: {
                type: "Point",
                coordinates: [139.7514, 35.6762]  // 渋谷駅
            },
            $maxDistance: 5000  // 5km以内
        }
    }
});

// エリア内検索
db.places.find({
    location: {
        $geoWithin: {
            $geometry: {
                type: "Polygon",
                coordinates: [[
                    [139.7, 35.6],
                    [139.8, 35.6],
                    [139.8, 35.7],
                    [139.7, 35.7],
                    [139.7, 35.6]
                ]]
            }
        }
    }
});
