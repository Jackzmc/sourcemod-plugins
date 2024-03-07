-- MySQL dump 10.13  Distrib 8.2.0, for Win64 (x86_64)
--
-- Host: 127.0.0.1    Database: left4dead2
-- ------------------------------------------------------
-- Server version	5.5.5-10.6.16-MariaDB-1:10.6.16+maria~deb11

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `bans`
--

DROP TABLE IF EXISTS `bans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `bans` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `steamid` varchar(32) NOT NULL,
  `reason` varchar(255) NOT NULL,
  `public_message` varchar(255) DEFAULT NULL,
  `ip` varchar(32) DEFAULT NULL,
  `expires` bigint(20) DEFAULT NULL,
  `timestamp` bigint(20) DEFAULT unix_timestamp(),
  `flags` smallint(6) NOT NULL DEFAULT 0,
  `expired` tinyint(1) GENERATED ALWAYS AS (ifnull(`expires`,0) > 1 and unix_timestamp() >= `expires`) VIRTUAL,
  `times_tried` smallint(6) NOT NULL DEFAULT 0,
  `executor` varchar(32) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ip` (`ip`),
  KEY `steamid` (`steamid`)
) ENGINE=InnoDB AUTO_INCREMENT=2250 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2024-03-06 18:22:26
