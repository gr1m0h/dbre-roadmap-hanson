// MongoDB ドキュメント設計パターン
// 使用方法: mongosh < document_design.js

// パターン1: 埋め込み (Embedding)
// ユースケース: 1対少数の関係、常に一緒に取得するデータ

db.articles.insertOne({
    _id: ObjectId(),
    title: "Introduction to MongoDB",
    author: "John Doe",
    content: "...",
    // コメントを埋め込み（少数の場合）
    comments: [
        {
            user: "Alice",
            text: "Great article!",
            created_at: new Date()
        },
        {
            user: "Bob",
            text: "Very helpful",
            created_at: new Date()
        }
    ],
    created_at: new Date()
});

// パターン2: 参照 (Referencing)
// ユースケース: 1対多数の関係、独立して更新するデータ

// articles コレクション
db.articles.insertOne({
    _id: ObjectId("article001"),
    title: "Advanced MongoDB",
    author_id: ObjectId("user001"),
    created_at: new Date()
});

// comments コレクション（別コレクション）
db.comments.insertMany([
    {
        _id: ObjectId(),
        article_id: ObjectId("article001"),
        user: "Alice",
        text: "Great!",
        created_at: new Date()
    },
    {
        _id: ObjectId(),
        article_id: ObjectId("article001"),
        user: "Bob",
        text: "Thanks!",
        created_at: new Date()
    }
]);

// $lookup でJOIN
db.articles.aggregate([
    { $match: { _id: ObjectId("article001") } },
    {
        $lookup: {
            from: "comments",
            localField: "_id",
            foreignField: "article_id",
            as: "comments"
        }
    },
    {
        $project: {
            title: 1,
            author_id: 1,
            comment_count: { $size: "$comments" },
            recent_comments: { $slice: ["$comments", 5] }
        }
    }
]);

// パターン3: バケットパターン (Bucketing)
// ユースケース: 時系列データ、IoTセンサーデータ

db.sensor_data.insertOne({
    sensor_id: "sensor_001",
    bucket_time: ISODate("2024-01-15T10:00:00Z"),
    measurements: [
        { time: ISODate("2024-01-15T10:00:15Z"), temp: 22.5, humidity: 45 },
        { time: ISODate("2024-01-15T10:01:15Z"), temp: 22.6, humidity: 46 },
        { time: ISODate("2024-01-15T10:02:15Z"), temp: 22.4, humidity: 45 }
    ],
    count: 3
});

// バケット検索
db.sensor_data.find({
    sensor_id: "sensor_001",
    bucket_time: {
        $gte: ISODate("2024-01-15T10:00:00Z"),
        $lt: ISODate("2024-01-15T11:00:00Z")
    }
});
