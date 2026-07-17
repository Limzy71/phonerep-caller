import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';
import { VoteType } from '../../generated/prisma/client';
import * as truecallerjs from 'truecallerjs';
import { SyncContactsDto } from './dto/sync-contacts.dto';

@Injectable()
export class PhoneLookupService {
  constructor(private readonly prisma: PrismaService) {}

  async lookupPhoneNumber(
    rawNumber: string,
    skipIncrement: boolean = false,
    deviceId: string = 'unknown-device',
    hasContactAccess: boolean = true,
  ) {
    // 0. Anti-Abuse Quota Enforcement for devices without contact access
    if (!skipIncrement && !hasContactAccess) {
      const todayString = new Date().toISOString().slice(0, 10);
      const log = await this.prisma.deviceSearchLog.findUnique({
        where: {
          deviceId_dateString: {
            deviceId: deviceId,
            dateString: todayString,
          },
        },
      });

      if (log && log.searchCount >= 1) {
        throw new HttpException(
          {
            code: 'QUOTA_EXCEEDED',
            message: 'Kuota pencarian gratis harian Anda (1x) telah habis. Kuota akan diperbarui besok pukul 07:00 WIB.',
            quota: 1,
            used: log.searchCount,
          },
          HttpStatus.FORBIDDEN,
        );
      }

      await this.prisma.deviceSearchLog.upsert({
        where: {
          deviceId_dateString: {
            deviceId: deviceId,
            dateString: todayString,
          },
        },
        create: {
          deviceId: deviceId,
          dateString: todayString,
          searchCount: 1,
        },
        update: {
          searchCount: {
            increment: 1,
          },
        },
      });
    }

    // Normalisasi nomor telepon: hapus spasi dan strip, serta ubah format 08/628 menjadi standar E.164 (+628)
    let number = rawNumber.trim().replace(/\s+/g, '').replace(/-/g, '');
    if (number.startsWith('0')) {
      number = '+62' + number.substring(1);
    } else if (number.startsWith('62') && !number.startsWith('+')) {
      number = '+' + number;
    }

    // Cari nomor telepon dengan eager loading (include: tags)
    const record = await this.prisma.phoneNumber.findUnique({
      where: {
        phoneNumber: number,
      },
      include: {
        tags: true,
      },
    });

    // Jika nomor ditemukan, tambahkan searchCount sebanyak 1 (kecuali skipIncrement aktif)
    if (record) {
      const updatedRecord = skipIncrement
        ? record
        : await this.prisma.phoneNumber.update({
            where: {
              phoneNumber: number,
            },
            data: {
              searchCount: {
                increment: 1,
              },
            },
            include: {
              tags: true,
            },
          });

      // Filter out tag sistem lama jika masih ada di database
      updatedRecord.tags = updatedRecord.tags
        .filter((t: any) =>
          !t.labelName.includes('Terverifikasi Otomatis') &&
          !t.labelName.includes('Belum Ada Label Nama') &&
          !t.labelName.startsWith('Operator: ')
        )
        .map((t: any) => ({
          ...t,
          labelName: t.labelName.replace(/^Nama:\s*/i, '').trim(),
        }));

      const computedCarrier = this.detectCarrier(number);
      let baseScore = 80.0;
      if (computedCarrier !== 'Operator Seluler Indonesia' && computedCarrier !== 'Unknown Carrier') {
        baseScore = 82.5;
      }

      let upvotesTotal = 0;
      let downvotesTotal = 0;
      for (const tag of updatedRecord.tags) {
        upvotesTotal += tag.upvotes;
        downvotesTotal += tag.downvotes;
      }
      
      let newTrustScore = baseScore + (upvotesTotal * 1.5) - (downvotesTotal * 3.5);
      const spamTags = updatedRecord.tags.filter((t: any) => t.isSpam || t.labelName.toLowerCase().includes('penipu') || t.labelName.toLowerCase().includes('spam'));
      for (const tag of spamTags) {
        if (tag.upvotes >= tag.downvotes && tag.upvotes > 0) {
          newTrustScore -= 25; 
        }
      }

      if (newTrustScore > 100) newTrustScore = 100;
      if (newTrustScore < 0) newTrustScore = 0;
      newTrustScore = parseFloat(newTrustScore.toFixed(1));

      if (newTrustScore !== updatedRecord.trustScore) {
        updatedRecord.trustScore = newTrustScore;
        // Update di background agar tidak memperlambat response
        this.prisma.phoneNumber.update({
          where: { id: updatedRecord.id },
          data: { trustScore: newTrustScore },
        }).catch(() => {});
      }

      return {
        found: true,
        phoneNumber: number,
        message: 'Informasi nomor telepon ditemukan.',
        data: {
          ...updatedRecord,
          carrier: computedCarrier,
        },
      };
    }

    // --- CARRIER & NAME RESOLUTION ---
    let actualName = 'Nomor Tidak Dikenal';
    let carrier = 'Unknown Carrier';
    let countryCode = 'ID';

    // 1. Deteksi lokal dulu: jika nomor Indonesia, langsung pakai detectCarrier() tanpa hit Truecaller
    //    Ini menghindari 429 rate-limit dari Truecaller untuk 99% kasus (nomor ID)
    const isIndonesianNumber = number.startsWith('+62') || number.startsWith('62') || number.startsWith('0');
    if (isIndonesianNumber) {
      carrier = this.detectCarrier(number);
      countryCode = 'ID';
    } else {
      // 2. Untuk nomor internasional, coba Truecaller — fallback ke detectCarrier jika gagal
      let tcData: any = null;
      try {
        if (process.env.TRUECALLER_TOKEN) {
          let cleanToken = process.env.TRUECALLER_TOKEN;
          if (cleanToken.startsWith('eyJ') && cleanToken.includes('.')) {
            try {
              const parsedJwt = JSON.parse(Buffer.from(cleanToken.split('.')[1], 'base64').toString());
              if (parsedJwt && parsedJwt.token) cleanToken = parsedJwt.token;
            } catch (e) { /* abaikan */ }
          }

          const tcResponse = await truecallerjs.search({
            number: number,
            countryCode: 'ID',
            installationId: cleanToken,
          });

          tcData = tcResponse.json();
          if (tcData && tcData.data && tcData.data[0]) {
            const contact: any = tcData.data[0];
            if (contact.name && contact.name !== 'unknown name') actualName = contact.name;
            if (contact.phone?.carrier) carrier = contact.phone.carrier;
            else if (contact.phones?.[0]?.carrier) carrier = contact.phones[0].carrier;
            if (contact.phone?.countryCode) countryCode = contact.phone.countryCode.toUpperCase();
            else if (contact.phones?.[0]?.countryCode) countryCode = contact.phones[0].countryCode.toUpperCase();
          }
        }
      } catch (err: any) {
        // Truecaller gagal (rate limit, dll) — fallback ke deteksi lokal
      }

      // Jika carrier dari Truecaller masih generik/unknown, gunakan deteksi lokal
      if (
        carrier === 'Unknown Carrier' ||
        carrier.toLowerCase().includes('roaming') ||
        carrier.toLowerCase().includes('global') ||
        carrier.toLowerCase().includes('local providers') ||
        carrier.toLowerCase().includes('voip') ||
        carrier.toLowerCase().includes('satellite') ||
        carrier.toLowerCase().includes('international')
      ) {
        carrier = this.detectCarrier(number);
      }
    }

    // 3. Susun tag komunitas yang asli (tanpa tag otomatis/sistem seperti 'Terverifikasi Otomatis' atau 'Operator:')
    const tagsToCreate: any[] = [];
    if (actualName && actualName !== 'Nomor Tidak Dikenal') {
      tagsToCreate.push({
        labelName: actualName,
        isSpam: false,
        upvotes: 2,
        downvotes: 0,
      });
    }

    // 4. Simpan nomor baru beserta tag otomatis ke database PostgreSQL
    const newRecord = await this.prisma.phoneNumber.create({
      data: {
        phoneNumber: number,
        countryCode: countryCode,
        searchCount: skipIncrement ? 0 : 1,
        trustScore: 82.5, // Skor awal aman untuk nomor terdeteksi operator sah
        tags: {
          create: tagsToCreate,
        },
      },
      include: {
        tags: true,
      },
    });

    return {
      found: true,
      phoneNumber: number,
      message: `Reputasi nomor telepon (${actualName !== 'Nomor Tidak Dikenal' ? actualName + ' • ' : ''}${carrier} - ${countryCode}) berhasil diperbarui.`,
      data: {
        ...newRecord,
        carrier: carrier,
      },
    };
  }

  private detectCarrier(number: string): string {
    const cleanNum = number.replace(/\s+/g, '').replace(/-/g, '');
    if (cleanNum.startsWith('+62') || cleanNum.startsWith('62') || cleanNum.startsWith('0')) {
      let normDigits = cleanNum;
      if (normDigits.startsWith('+62')) {
        normDigits = '0' + normDigits.substring(3);
      } else if (normDigits.startsWith('62')) {
        normDigits = '0' + normDigits.substring(2);
      }

      if (normDigits.startsWith('021')) return 'Telkom Indonesia (PSTN Jakarta / Jabodetabek)';
      if (normDigits.startsWith('022')) return 'Telkom Indonesia (PSTN Bandung)';
      if (normDigits.startsWith('031')) return 'Telkom Indonesia (PSTN Surabaya)';
      if (normDigits.startsWith('024')) return 'Telkom Indonesia (PSTN Semarang)';
      if (normDigits.startsWith('0274')) return 'Telkom Indonesia (PSTN Yogyakarta)';
      if (normDigits.startsWith('061')) return 'Telkom Indonesia (PSTN Medan)';
      if (normDigits.startsWith('0411')) return 'Telkom Indonesia (PSTN Makassar)';
      if (normDigits.startsWith('0361')) return 'Telkom Indonesia (PSTN Bali)';
      if (normDigits.startsWith('0778')) return 'Telkom Indonesia (PSTN Batam)';
      if (/^0[2345679]/.test(normDigits)) return 'Telkom Indonesia (Telepon PSTN / Fixed Line)';

      const prefix4 = normDigits.substring(0, 4);
      if (['0811', '0812', '0813', '0821', '0822', '0823', '0851', '0852', '0853'].includes(prefix4)) return 'Telkomsel';
      if (['0817', '0818', '0819', '0859', '0877', '0878'].includes(prefix4)) return 'XL Axiata';
      if (['0838', '0831', '0832', '0833'].includes(prefix4)) return 'AXIS (XL Axiata)';
      if (['0814', '0815', '0816', '0855', '0856', '0857', '0858'].includes(prefix4)) return 'Indosat Ooredoo Hutchison';
      if (['0881', '0882', '0883', '0884', '0885', '0886', '0887', '0888', '0889'].includes(prefix4)) return 'Smartfren';
      if (['0895', '0896', '0897', '0898', '0899'].includes(prefix4)) return 'Tri (3 / IOH)';
      return 'Operator Seluler Indonesia';
    }
    if (cleanNum.startsWith('+1')) return 'AT&T / Verizon / T-Mobile US';
    if (cleanNum.startsWith('+44')) return 'EE / Vodafone / O2 UK';
    if (cleanNum.startsWith('+65')) return 'Singtel / StarHub / M1';
    if (cleanNum.startsWith('+60')) return 'Maxis / CelcomDigi / U Mobile';
    return 'Operator Telekomunikasi Internasional';
  }


  async createTag(phoneNumberId: string, labelName: string, userId?: string) {
    // Verifikasi apakah phoneNumberId ada
    const phone = await this.prisma.phoneNumber.findUnique({
      where: { id: phoneNumberId },
    });

    if (!phone) {
      return {
        success: false,
        message: 'Nomor telepon tidak ditemukan dalam sistem.',
        data: null,
      };
    }

    // Sanitasi input labelName agar bebas dari skrip berbahaya (Anti XSS) & batasi maksimal 60 karakter
    const cleanLabel = (labelName || '').trim().replace(/<[^>]*>?/gm, '').substring(0, 60).trim();
    if (!cleanLabel) {
      return {
        success: false,
        message: 'Nama label tidak valid atau terlalu pendek (minimal 2 karakter).',
        data: null,
      };
    }

    let validUserId: string | null = null;
    if (userId) {
      // Normalisasi userId agar konsisten dengan format E.164
      let normUserId = userId.trim().replace(/[\s\-\(\)\.]+/g, '');
      if (normUserId.startsWith('0')) normUserId = '+62' + normUserId.substring(1);
      else if (normUserId.startsWith('62') && !normUserId.startsWith('+')) normUserId = '+' + normUserId;
      
      try {
        const userRecord = await this.prisma.user.upsert({
          where: { id: normUserId },
          update: {},
          create: {
            id: normUserId,
            email: `${normUserId.replace('+', '')}@mobile.phonerep.komunitas`,
            password: 'mobile-tag-hash',
            name: 'Pengguna Komunitas',
          },
        });
        validUserId = userRecord.id;
      } catch (e) {
        validUserId = null;
      }
    }

    const existingTag = await this.prisma.tag.findFirst({
      where: {
        phoneNumberId,
        labelName: {
          equals: cleanLabel,
          mode: 'insensitive',
        },
      },
    });

    if (existingTag) {
      if (validUserId) {
        // Gunakan voteTag untuk menangani logika double-vote & increment
        return this.voteTag(existingTag.id, validUserId, 'UPVOTE');
      } else {
        // Jika tidak ada userId (jarang terjadi sekarang), cukup increment upvotes secara langsung
        const updatedTag = await this.prisma.tag.update({
          where: { id: existingTag.id },
          data: { upvotes: { increment: 1 } },
        });
        return {
          success: true,
          message: 'Label tag sudah ada dan jumlah dukungan berhasil ditambahkan.',
          data: updatedTag,
        };
      }
    }

    const newTag = await this.prisma.tag.create({
      data: {
        phoneNumberId,
        labelName: cleanLabel,
        userId: validUserId,
        isSpam: false,
        upvotes: 1,
      },
    });

    if (validUserId) {
      // Catat vote pertama untuk mencegah double vote nantinya
      await this.prisma.tagVote.create({
        data: {
          tagId: newTag.id,
          userId: validUserId,
          voteType: 'UPVOTE',
        },
      }).catch(() => {});
    }

    return {
      success: true,
      message: 'Label tag berhasil ditambahkan.',
      data: newTag,
    };
  }

  async voteTag(tagId: string, userId: string, voteType: 'UPVOTE' | 'DOWNVOTE') {
    // 1. Cek apakah tag ada
    const tag = await this.prisma.tag.findUnique({
      where: { id: tagId },
    });

    if (!tag) {
      return {
        success: false,
        message: 'Label tag tidak ditemukan.',
        data: null,
      };
    }

    // 2. Pastikan user terdaftar di database (jika belum, auto-create untuk pengguna aplikasi mobile komunitas)
    // Normalisasi userId
    let normUserId = userId.trim().replace(/[\s\-\(\)\.]+/g, '');
    if (normUserId.startsWith('0')) normUserId = '+62' + normUserId.substring(1);
    else if (normUserId.startsWith('62') && !normUserId.startsWith('+')) normUserId = '+' + normUserId;

    let user = await this.prisma.user.findUnique({
      where: { id: normUserId },
    });

    if (!user) {
      try {
        user = await this.prisma.user.create({
          data: {
            id: normUserId,
            email: `${normUserId.replace('+', '')}@mobile.phonerep.komunitas`,
            password: 'mobile-vote-hash',
            name: 'Pengguna Komunitas',
          },
        });
      } catch (e) {
        return {
          success: false,
          message: 'ID pengguna tidak valid atau gagal diverifikasi.',
          data: null,
        };
      }
    }

    // 3. Cek apakah vote sebelumnya sudah ada
    const existingVote = await this.prisma.tagVote.findUnique({
      where: {
        tagId_userId: {
          tagId,
          userId: normUserId,
        },
      },
    });

    if (existingVote) {
      if (existingVote.voteType === voteType) {
        return {
          success: true,
          message: 'Anda sudah memberikan penilaian pada label ini.',
          data: tag,
        };
      }

      // Update voteType di tabel tagVote
      await this.prisma.tagVote.update({
        where: { id: existingVote.id },
        data: { voteType: voteType as VoteType },
      });

      // Sesuaikan penghitung di tabel tag
      const updatedTag = await this.prisma.tag.update({
        where: { id: tagId },
        data:
          voteType === 'UPVOTE'
            ? { upvotes: { increment: 1 }, downvotes: { decrement: 1 } }
            : { upvotes: { decrement: 1 }, downvotes: { increment: 1 } },
      });

      return {
        success: true,
        message: `Penilaian berhasil diperbarui.`,
        data: updatedTag,
      };
    }

    // Jika belum ada vote sebelumnya, buat rekor tagVote baru
    await this.prisma.tagVote.create({
      data: {
        tagId,
        userId,
        voteType: voteType as VoteType,
      },
    });

    const updatedTag = await this.prisma.tag.update({
      where: { id: tagId },
      data:
        voteType === 'UPVOTE'
          ? { upvotes: { increment: 1 } }
          : { downvotes: { increment: 1 } },
    });

    return {
      success: true,
      message: `Penilaian berhasil dicatat.`,
      data: updatedTag,
    };
  }

  async syncContacts(dto: SyncContactsDto) {
    if (!dto || !dto.contacts || !Array.isArray(dto.contacts) || dto.contacts.length === 0) {
      return {
        success: false,
        message: 'Daftar kontak tidak boleh kosong.',
        syncedCount: 0,
      };
    }

    // Proteksi Keamanan: Batasi maksimal 500 kontak per batch untuk mencegah serangan DOS / pembebanan server
    if (dto.contacts.length > 500) {
      return {
        success: false,
        message: 'Maksimal 500 kontak dapat disinkronkan dalam satu permintaan.',
        syncedCount: 0,
      };
    }

    let validUserId: string | null = null;
    if (dto.userId) {
      // Normalisasi userId
      let normUserId = dto.userId.trim().replace(/[\s\-\(\)\.]+/g, '');
      if (normUserId.startsWith('0')) normUserId = '+62' + normUserId.substring(1);
      else if (normUserId.startsWith('62') && !normUserId.startsWith('+')) normUserId = '+' + normUserId;

      try {
        const userRecord = await this.prisma.user.upsert({
          where: { id: normUserId },
          update: {},
          create: {
            id: normUserId,
            email: `${normUserId.replace('+', '')}@mobile.phonerep.komunitas`,
            password: 'mobile-app-sync-hash',
            name: 'Mobile App User',
          },
        });
        validUserId = userRecord.id;
      } catch (e) {
        // Jika gagal upsert karena alasan apa pun, abaikan userId agar proses sync tidak gagal
        validUserId = null;
      }
    }

    let syncedCount = 0;

    for (const item of dto.contacts) {
      try {
        if (!item || !item.phoneNumber || !item.name) continue;

        let number = item.phoneNumber.trim().replace(/[\s\-\(\)\.]+/g, '');
        if (number.startsWith('0')) {
          number = '+62' + number.substring(1);
        } else if (number.startsWith('62') && !number.startsWith('+')) {
          number = '+' + number;
        }

        if (!number || number.length < 5 || (!number.startsWith('+') && !/^\d+$/.test(number))) {
          continue;
        }

        // Sanitasi input: hapus karakter HTML / Script (Anti-XSS & Injection) dan batasi maksimal 60 karakter
        const cleanName = item.name.trim().replace(/<[^>]*>?/gm, '').substring(0, 60).trim();
        if (!cleanName) continue;

        let phoneRecord = await this.prisma.phoneNumber.findUnique({
          where: { phoneNumber: number },
        });

        let countryCode = 'ID';
        if (!number.startsWith('+62')) {
          if (number.startsWith('+1')) countryCode = 'US';
          else if (number.startsWith('+44')) countryCode = 'UK';
          else if (number.startsWith('+65')) countryCode = 'SG';
          else if (number.startsWith('+60')) countryCode = 'MY';
          else countryCode = 'GLOBAL';
        }

        if (!phoneRecord) {
          try {
            phoneRecord = await this.prisma.phoneNumber.create({
              data: {
                phoneNumber: number,
                countryCode: countryCode,
                searchCount: 0,
                trustScore: 80.0,
                tags: {
                  create: [
                    {
                      labelName: cleanName,
                      userId: validUserId,
                      isSpam: false,
                      upvotes: 1,
                      downvotes: 0,
                    },
                  ],
                },
              },
            });

            // Catat vote awal jika user terverifikasi
            if (validUserId) {
              const newTag = await this.prisma.tag.findFirst({
                where: { phoneNumberId: phoneRecord.id, labelName: cleanName },
              });
              if (newTag) {
                await this.prisma.tagVote.create({
                  data: {
                    tagId: newTag.id,
                    userId: validUserId,
                    voteType: 'UPVOTE',
                  },
                }).catch(() => {});
              }
            }

            syncedCount++;
            continue; // Lanjut ke kontak berikutnya (mencegah double increment)
          } catch (createErr) {
            // Jika terjadi race condition / nomor duplikat bersamaan, ambil ulang dan tambahkan tag
            phoneRecord = await this.prisma.phoneNumber.findUnique({
              where: { phoneNumber: number },
            });
            if (!phoneRecord) continue;
          }
        }

        if (phoneRecord) {
          const existingTag = await this.prisma.tag.findFirst({
            where: {
              phoneNumberId: phoneRecord.id,
              labelName: {
                equals: cleanName,
                mode: 'insensitive',
              },
            },
          });

          if (existingTag) {
            // Periksa apakah user yang sama sudah vote untuk mencegah double vote
            let alreadyVoted = false;
            if (validUserId) {
              const vote = await this.prisma.tagVote.findUnique({
                where: {
                  tagId_userId: {
                    tagId: existingTag.id,
                    userId: validUserId,
                  },
                },
              });
              if (vote) {
                alreadyVoted = true;
              }
            }

            if (!alreadyVoted) {
              await this.prisma.tag.update({
                where: { id: existingTag.id },
                data: { upvotes: { increment: 1 } },
              });
              if (validUserId) {
                await this.prisma.tagVote.create({
                  data: {
                    tagId: existingTag.id,
                    userId: validUserId,
                    voteType: 'UPVOTE',
                  },
                }).catch(() => {});
              }
            }
          } else {
            const newTag = await this.prisma.tag.create({
              data: {
                phoneNumberId: phoneRecord.id,
                labelName: cleanName,
                userId: validUserId,
                isSpam: false,
                upvotes: 1,
                downvotes: 0,
              },
            });
            if (validUserId) {
              await this.prisma.tagVote.create({
                data: {
                  tagId: newTag.id,
                  userId: validUserId,
                  voteType: 'UPVOTE',
                },
              }).catch(() => {});
            }
          }
          syncedCount++;
        }
      } catch (itemErr: any) {
        // Abaikan kontak yang bermasalah (misal karakter ilegal/emoticon aneh) agar tidak menyebabkan 500 Server Error
        console.error('Error saat menyinkronkan kontak individual:', item?.phoneNumber, item?.name, itemErr?.message);
        continue;
      }
    }

    return {
      success: true,
      message: `${syncedCount} kontak berhasil disinkronkan ke jaringan PhoneRep.`,
      syncedCount,
    };
  }

  private otpStore = new Map<string, { code: string; expiresAt: number; attempts: number; lockoutUntil?: number; lastSentAt?: number }>();

  async sendOtp(rawNumber: string, isResend = false): Promise<{ success: boolean; message: string; resendAvailableAt?: number }> {
    let number = rawNumber.trim().replace(/\s+/g, '').replace(/-/g, '');
    if (number.startsWith('0')) {
      number = '+62' + number.substring(1);
    } else if (number.startsWith('62') && !number.startsWith('+')) {
      number = '+' + number;
    }

    // Cek apakah nomor sedang dalam masa pemblokiran sementara (Temporary Ban)
    const existing = this.otpStore.get(number) || this.otpStore.get(rawNumber.trim());
    if (existing && existing.lockoutUntil && Date.now() < existing.lockoutUntil) {
      const remainingSec = Math.ceil((existing.lockoutUntil - Date.now()) / 1000);
      return {
        success: false,
        message: `Kode OTP salah 5 kali. Silakan coba kembali dalam ${remainingSec} detik.`,
        lockoutUntil: existing.lockoutUntil,
      } as any;
    } else if (existing && existing.lockoutUntil && Date.now() >= existing.lockoutUntil) {
      // Jika masa blokir 3 menit sudah selesai, reset jumlah percobaan agar pengguna tidak terblokir lagi pada kesalahan pertama
      existing.attempts = 0;
      delete existing.lockoutUntil;
    }

    // Jika bukan klik Kirim Ulang paksa (!isResend) DAN OTP sebelumnya belum expired, gunakan kembali OTP tersebut! Ini mencegah spam pesan WA & mencegah reset kesalahan (attempts) saat bolak-balik ke halaman daftar.
    if (!isResend && existing && Date.now() < existing.expiresAt) {
      return {
        success: true,
        message: 'Kode OTP sebelumnya masih aktif.',
        resendAvailableAt: existing.lastSentAt ? existing.lastSentAt + 60000 : Date.now() + 60000,
      };
    }

    // Jika pengguna menekan tombol Kirim Ulang (isResend == true), cek apakah cooldown 60 detik sudah terpenuhi
    if (isResend && existing && existing.lastSentAt && Date.now() < existing.lastSentAt + 60000) {
      return {
        success: true,
        message: 'Harap tunggu hingga waktu jeda kirim ulang selesai.',
        resendAvailableAt: existing.lastSentAt + 60000,
      };
    }

    // Generate 6-digit random code
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes
    const lastSentAt = Date.now();

    // 💡 Penting: Selalu pertahankan jumlah percobaan salah (existing.attempts) agar tidak bisa dicheat dengan minta kode baru atau bolak-balik halaman pendaftaran!
    const recordData = { code, expiresAt, lastSentAt, attempts: existing ? existing.attempts : 0 };
    this.otpStore.set(number, recordData);
    this.otpStore.set(rawNumber.trim(), recordData);

    // 💡 Selalu log ke console agar developer/user bisa langsung copy jika gateway WA tertunda/offline
    console.log(`\n======================================================`);
    console.log(`🔑 [KODE OTP] Untuk nomor: ${number}`);
    console.log(`👉 KODE OTP ANDA: ${code}`);
    console.log(`======================================================\n`);

    const token = process.env.FONNTE_TOKEN;
    if (!token) {
      console.warn('FONNTE_TOKEN is not set in .env. OTP stored locally for dev mode:', code);
      return {
        success: true,
        message: 'Kode OTP berhasil dibuat (Mode Simulasi)',
        resendAvailableAt: lastSentAt + 60000,
      };
    }

    try {
      const axios = require('axios');
      let fonnteTarget = number.replace('+', '');
      const messageText = `*PhoneRep Security*\n\nKode verifikasi OTP Anda adalah: *${code}*\n\nKode ini berlaku selama 5 menit. JANGAN bagikan kode ini kepada siapapun demi keamanan data Anda.`;

      const response = await axios.post(
        'https://api.fonnte.com/send',
        {
          target: fonnteTarget,
          message: messageText,
          countryCode: '62',
        },
        {
          headers: {
            Authorization: token,
          },
        },
      );

      console.log('Fonnte response:', response.data);
      return {
        success: true,
        message: 'Kode OTP berhasil dikirim ke nomor WhatsApp Anda.',
        resendAvailableAt: lastSentAt + 60000,
      };
    } catch (error: any) {
      console.error('Error sending OTP via Fonnte:', error?.response?.data || error.message);
      return {
        success: false,
        message: 'Gagal mengirimkan kode OTP ke WhatsApp. Silakan coba lagi.',
      };
    }
  }

  async verifyOtp(rawNumber: string, code: string): Promise<{ success: boolean; message: string }> {
    let number = rawNumber.trim().replace(/\s+/g, '').replace(/-/g, '');
    if (number.startsWith('0')) {
      number = '+62' + number.substring(1);
    } else if (number.startsWith('62') && !number.startsWith('+')) {
      number = '+' + number;
    }

    const record = this.otpStore.get(number) || this.otpStore.get(rawNumber.trim());
    if (!record) {
      return {
        success: false,
        message: 'Kode OTP tidak ditemukan atau belum diminta. Silakan klik kirim ulang.',
      };
    }

    // Cek Temporary Ban
    if (record.lockoutUntil && Date.now() < record.lockoutUntil) {
      const remainingSec = Math.ceil((record.lockoutUntil - Date.now()) / 1000);
      return {
        success: false,
        message: `Kode OTP salah 5 kali. Silakan coba kembali dalam ${remainingSec} detik.`,
        lockoutUntil: record.lockoutUntil,
      } as any;
    } else if (record.lockoutUntil && Date.now() >= record.lockoutUntil) {
      // Jika masa blokir 3 menit sudah selesai, reset jumlah percobaan agar pengguna tidak langsung terblokir lagi
      record.attempts = 0;
      delete record.lockoutUntil;
    }

    // Cek kedaluwarsa OTP
    if (Date.now() > record.expiresAt) {
      this.otpStore.delete(number);
      this.otpStore.delete(rawNumber.trim());
      return {
        success: false,
        message: 'Kode OTP sudah kedaluwarsa. Silakan minta kode baru.',
      };
    }

    // Cek kesesuaian kode OTP
    if (record.code !== code) {
      record.attempts++;
      if (record.attempts >= 5) {
        // Berikan Temporary Ban selama 3 menit (180.000 ms)
        record.lockoutUntil = Date.now() + 3 * 60 * 1000;
        return {
          success: false,
          message: 'Kode OTP salah 5 kali. Silakan coba kembali dalam 180 detik.',
          lockoutUntil: record.lockoutUntil,
        } as any;
      }
      return {
        success: false,
        message: `Kode OTP salah (${record.attempts}/5 percobaan). Silakan periksa kembali pesan WhatsApp Anda.`,
      };
    }

    // Verifikasi sukses, hapus data OTP dari memori
    this.otpStore.delete(number);
    this.otpStore.delete(rawNumber.trim());

    return {
      success: true,
      message: 'Verifikasi kepemilikan nomor telepon berhasil!',
    };
  }

  async getAnalytics() {
    const totalNumbers = await this.prisma.phoneNumber.count();
    const totalTags = await this.prisma.tag.count();
    const topSearchedNumbers = await this.prisma.phoneNumber.findMany({
      orderBy: {
        searchCount: 'desc',
      },
      take: 3,
    });

    return {
      totalNumbers,
      totalTags,
      topSearchedNumbers,
    };
  }

  async resetPhoneNumberData(rawNumber: string): Promise<{ success: boolean; message: string }> {
    let numberE164 = rawNumber.trim().replace(/\s+/g, '').replace(/-/g, '');
    let number08 = numberE164;
    let number628 = numberE164;

    if (numberE164.startsWith('0')) {
      numberE164 = '+62' + numberE164.substring(1);
      number08 = '0' + numberE164.substring(3);
      number628 = '62' + numberE164.substring(3);
    } else if (numberE164.startsWith('62') && !numberE164.startsWith('+')) {
      numberE164 = '+' + numberE164;
      number08 = '0' + numberE164.substring(3);
      number628 = '62' + numberE164.substring(3);
    } else if (numberE164.startsWith('+62')) {
      number08 = '0' + numberE164.substring(3);
      number628 = '62' + numberE164.substring(3);
    }

    const allNumberVariants = Array.from(new Set([numberE164, number08, number628, rawNumber.trim()]));

    try {
      // 1. Cari semua kemungkinan User yang terkait (via email dengan semua variasi nomor)
      const emailVariants = allNumberVariants.map((n) => `${n}@mobile.phonerep.komunitas`);
      const users = await this.prisma.user.findMany({
        where: {
          OR: [
            { id: { in: allNumberVariants } }, // userId tersimpan sebagai nomor HP langsung
            { email: { in: emailVariants } },   // email berformat nomor@domain
          ],
        },
        select: { id: true },
      });

      // Kumpulkan semua kemungkinan userId (UUID dari tabel User + variasi nomor HP langsung)
      const userUuids = users.map((u) => u.id);
      const allUserIdVariants = Array.from(new Set([...allNumberVariants, ...userUuids]));

      // 2. Temukan semua Tag yang dibuat oleh pengguna ini (pakai semua varian ID)
      const userTags = await this.prisma.tag.findMany({
        where: {
          userId: {
            in: allUserIdVariants,
          },
        },
        select: {
          id: true,
          phoneNumberId: true,
        },
      });

      const tagIds = userTags.map((t) => t.id);
      const syncedPhoneIds = Array.from(new Set(userTags.map((t) => t.phoneNumberId)));

      // 3. Hapus semua TagVote terkait
      if (tagIds.length > 0) {
        await this.prisma.tagVote.deleteMany({
          where: { tagId: { in: tagIds } },
        });

        // 4. Hapus semua Tag yang pernah dibuat pengguna ini
        await this.prisma.tag.deleteMany({
          where: { id: { in: tagIds } },
        });
      }

      // 5. Hapus juga semua TagVote yang dilakukan oleh user ini (bukan hanya yang dibuat)
      if (userUuids.length > 0) {
        await this.prisma.tagVote.deleteMany({
          where: { userId: { in: allUserIdVariants } },
        });
      }

      // 6. Bersihkan nomor telepon yang tidak punya tag lagi (orphan cleanup)
      if (syncedPhoneIds.length > 0) {
        for (const pid of syncedPhoneIds) {
          const remainingTagsCount = await this.prisma.tag.count({
            where: { phoneNumberId: pid },
          });
          if (remainingTagsCount === 0) {
            await this.prisma.phoneNumber.delete({
              where: { id: pid },
            }).catch(() => {});
          }
        }
      }

      // 7. Hapus nomor telepon milik pengguna itu sendiri dari tabel phoneNumber
      await this.prisma.phoneNumber.deleteMany({
        where: {
          phoneNumber: {
            in: allNumberVariants,
          },
        },
      });

      // 8. Hapus akun User dari tabel users
      await this.prisma.user.deleteMany({
        where: {
          OR: [
            { id: { in: allUserIdVariants } },
            { email: { in: emailVariants } },
          ],
        },
      });

      // 9. Bersihkan cache OTP
      for (const variant of allNumberVariants) {
        this.otpStore.delete(variant);
      }

      return {
        success: true,
        message: `Seluruh akun, riwayat, dan data kontak yang disinkronkan untuk nomor ${numberE164} berhasil dihapus permanen dari database.`,
      };
    } catch (error: any) {
      console.error('Error resetting phone data:', error);
      return {
        success: false,
        message: `Gagal menghapus data: ${error.message}`,
      };
    }
  }

  // ==========================================
  // DATA RETENTION & AGGREGATION LOGIC (BE)
  // ==========================================

  /**
   * Cron Job: Berjalan otomatis setiap pukul 00:00 (Tengah Malam)
   * Menghapus riwayat pencarian profil yang lebih lama dari 60 hari untuk menjaga performa database.
   */
  @Cron(CronExpression.EVERY_DAY_AT_MIDNIGHT)
  async purgeExpiredProfileSearchHistories() {
    try {
      const sixtyDaysAgo = new Date();
      sixtyDaysAgo.setDate(sixtyDaysAgo.getDate() - 60);

      const deleted = await this.prisma.profileSearchHistory.deleteMany({
        where: {
          lastSearchedAt: {
            lt: sixtyDaysAgo,
          },
        },
      });

      if (deleted.count > 0) {
        console.log(`[Data Retention Cron] Berhasil membersihkan ${deleted.count} riwayat pencarian profil lama (> 60 hari).`);
      }
    } catch (error) {
      console.error('[Data Retention Cron] Gagal melakukan purge riwayat:', error);
    }
  }

  /**
   * Helper: Mencatat atau memperbarui (agregasi) riwayat saat seseorang memeriksa nomor telepon.
   * Jika user yang sama sudah mencari nomor target sebelumnya, cukup increment searchCount (+1) & update lastSearchedAt.
   */
  async recordProfileSearchHistory(searcherUserId: string | null, targetPhoneId: string) {
    if (!searcherUserId) return; // Jika anonim tanpa akun, tidak dicatat di profil searchers

    try {
      const existing = await this.prisma.profileSearchHistory.findUnique({
        where: {
          searcherUserId_targetPhoneId: {
            searcherUserId,
            targetPhoneId,
          },
        },
      });

      if (existing) {
        await this.prisma.profileSearchHistory.update({
          where: { id: existing.id },
          data: {
            searchCount: { increment: 1 },
            lastSearchedAt: new Date(),
          },
        });
      } else {
        await this.prisma.profileSearchHistory.create({
          data: {
            searcherUserId,
            targetPhoneId,
            searchCount: 1,
            lastSearchedAt: new Date(),
          },
        });
      }
    } catch (error) {
      console.error('Error recording profile search history:', error);
    }
  }

  /**
   * Helper: Mengambil daftar riwayat orang yang memeriksa nomor pengguna (maksimal 100 terbaru / paginated)
   * Catatan Monetisasi (Ditangguhkan):
   * Saat ini (Tahap Awal), semua pengguna dapat melihat riwayat 60 hari penuh.
   * Di masa depan, buka komentar logika di bawah untuk membatasi pengguna gratis hanya melihat 24 jam.
   */
  async getPhoneSearchers(targetPhoneId: string, limit: number = 100, isPremium: boolean = false) {
    const whereClause: any = {
      targetPhoneId,
    };

    /* 
    // TODO: Aktifkan kembali saat siap monetisasi ketat
    // Jika BUKAN Premium (Gratis), batasi pencarian hanya 24 jam terakhir (Opsi B - FOMO)
    if (!isPremium) {
      const twentyFourHoursAgo = new Date();
      twentyFourHoursAgo.setDate(twentyFourHoursAgo.getDate() - 1);
      whereClause.lastSearchedAt = {
        gte: twentyFourHoursAgo,
      };
    }
    */

    return this.prisma.profileSearchHistory.findMany({
      where: whereClause,
      take: limit,
      orderBy: {
        lastSearchedAt: 'desc',
      },
      include: {
        searcherUser: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
            tags: {
              select: { labelName: true },
              take: 20,
            },
          },
        },
      },
    });
  }
}
